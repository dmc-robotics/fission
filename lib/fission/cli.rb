# frozen_string_literal: true

module Fission
  class CLI
    USAGE = <<~TEXT
      Usage:
        fission combine  [options] FILE1 [ANGLE1] FILE2 [ANGLE2 FILE3 ...]
        fission validate FILE [FILE ...]
        fission codes

      Commands:
        combine    Combine multiple CNC files, with optional A-axis rotations between setups
        validate   Validate G-code files for Carvera compatibility
        codes      List all supported Carvera G-codes and M-codes

      Options:
        -o, --output FILE    Output file (default: stdout)
        -h, --help           Show this help message
        -v, --version        Show version

      Examples:
        fission combine -o merged.nc roughing.nc finishing.nc
        fission combine -o part.nc front.nc 90 right.nc 180 back.nc
        fission combine -o part.nc rough.nc finish.nc 90 side_rough.nc side_finish.nc
        fission validate roughing.nc finishing.nc
    TEXT

    def initialize(argv)
      @argv = argv.dup
    end

    def run
      if @argv.empty?
        puts USAGE
        return 0
      end

      output_file = extract_output_option

      if @argv.include?("-h") || @argv.include?("--help")
        puts USAGE
        return 0
      end

      if @argv.include?("-v") || @argv.include?("--version")
        puts "fission #{Fission::VERSION}"
        return 0
      end

      command = @argv.shift
      case command
      when "combine"
        run_combine(output_file)
      when "validate"
        run_validate
      when "codes"
        Codes.print
        0
      else
        $stderr.puts "Unknown command: #{command}"
        $stderr.puts USAGE
        1
      end
    rescue Error => e
      $stderr.puts "Error: #{e.message}"
      1
    rescue Errno::ENOENT => e
      $stderr.puts "Error: #{e.message}"
      1
    end

    private

    def extract_output_option
      output_file = nil
      idx = @argv.index("-o") || @argv.index("--output")
      if idx
        @argv.delete_at(idx)
        output_file = @argv.delete_at(idx)
        raise Error, "Missing output filename after -o/--output" unless output_file
      end
      output_file
    end

    def run_combine(output_file)
      if @argv.length < 2
        $stderr.puts "Error: combine requires at least two files"
        $stderr.puts USAGE
        return 1
      end

      steps = parse_args(@argv)
      file_count = steps.count { |s| s.is_a?(GcodeFile) }
      if file_count < 2
        $stderr.puts "Error: combine requires at least two files"
        $stderr.puts USAGE
        return 1
      end
      combiner = Combiner.new(steps)

      input_results = combiner.validate_inputs
      return 1 if report_file_validation(input_results)

      result = combiner.combine
      combined_validator = combiner.validate_combined
      report_combined_validation(combined_validator)
      return 1 unless combined_validator.errors.empty?

      write_output(result, output_file)
      0
    end

    def run_validate
      if @argv.empty?
        $stderr.puts "Error: validate requires at least one file"
        $stderr.puts USAGE
        return 1
      end

      has_errors = false
      @argv.each do |path|
        file = GcodeFile.new(path)
        validator = file.validator
        validator.errors.each do |e|
          $stderr.puts format_result(file.filename, e, :error)
          has_errors = true
        end
        validator.warnings.each do |w|
          $stderr.puts format_result(file.filename, w, :warning)
        end
        print_summary(file.filename, validator) if validator.errors.empty?
      end

      has_errors ? 1 : 0
    end

    def parse_args(args)
      args.map do |arg|
        if arg.match?(/\A-?\d+(\.\d+)?\z/)
          Float(arg)
        else
          raise Error, "Unknown option: #{arg}" if arg.start_with?("-")
          GcodeFile.new(arg)
        end
      end
    end

    def report_file_validation(results)
      has_errors = false
      results[:errors].each do |entry|
        $stderr.puts format_result(entry[:file], entry[:result], :error)
        has_errors = true
      end
      results[:warnings].each do |entry|
        $stderr.puts format_result(entry[:file], entry[:result], :warning)
      end
      has_errors
    end

    def report_combined_validation(validator)
      validator.errors.each do |e|
        $stderr.puts format_result("combined output", e, :error)
      end
      validator.warnings.each do |w|
        $stderr.puts format_result("combined output", w, :warning)
      end
    end

    def print_summary(filename, validator)
      green = $stderr.tty? ? "\e[32m" : ""
      reset = $stderr.tty? ? "\e[0m" : ""
      $stderr.puts "#{green}#{filename}: ok#{reset}"
      $stderr.puts "  Units: #{validator.units || "unknown"}"
      if validator.tools.empty?
        $stderr.puts "  Tools: none"
      else
        validator.tools.each do |tool|
          desc = tool[:description] ? " - #{tool[:description]}" : ""
          $stderr.puts "  T#{tool[:number]}#{desc}"
        end
      end
    end

    COLORS = { error: "\e[31m", warning: "\e[33m" }.freeze

    def format_result(source, result, type)
      color = $stderr.tty? ? COLORS[type] : ""
      reset = $stderr.tty? ? "\e[0m" : ""
      "#{color}#{source}:#{result.line_number}: #{type}: #{result.message}#{reset}"
    end

    def write_output(content, output_file)
      if output_file
        File.write(output_file, content)
        $stderr.puts "Wrote #{output_file}"
      else
        puts content
      end
    end
  end
end
