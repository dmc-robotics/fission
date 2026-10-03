# frozen_string_literal: true

module Fission
  # Combines multiple GcodeFile objects into a single G-code program.
  #
  # Accepts an ordered list of steps — each is either a GcodeFile or a numeric
  # angle (for A-axis rotation). Files are concatenated with the first file's
  # header and last file's footer. Rotation angles insert spindle stop, Z retract,
  # and G0 A<angle> commands between file bodies.
  class Combiner
    attr_reader :steps

    # @param steps [Array<GcodeFile, Numeric>] ordered mix of files and rotation angles
    def initialize(steps)
      @steps = steps
      validate!
    end

    def combine
      lines = []

      # Use header from the first file
      lines.concat(files.first.header)

      @steps.each do |step|
        if step.is_a?(GcodeFile)
          lines << ""
          lines << "(--- Begin: #{step.filename} ---)"
          lines.concat(header_comments(step))
          lines.concat(step.body)
          lines << "(--- End: #{step.filename} ---)"
        else
          angle = step
          lines << ""
          lines << "(--- Rotate A-axis to #{angle} degrees ---)"
          lines << "M5"
          lines << "G28 G91 Z0"
          lines << "G90"
          lines << "G0 A#{format_angle(angle)}"
          lines << ""
        end
      end

      # Use footer from the last file
      lines.concat(files.last.footer)

      @combined_lines = lines
      lines.join("\n") + "\n"
    end

    def validate_combined
      raise "Must call #combine before #validate_combined" unless @combined_lines

      Validator.new(@combined_lines)
    end

    def validate_inputs
      errors = []
      warnings = []
      files.each do |file|
        file.validation_errors.each do |e|
          errors << { file: file.filename, result: e }
        end
        file.validation_warnings.each do |w|
          warnings << { file: file.filename, result: w }
        end
      end
      { errors: errors, warnings: warnings }
    end

    private

    def files
      @files ||= @steps.select { |s| s.is_a?(GcodeFile) }
    end

    def validate!
      raise Error, "At least two files are required" if files.length < 2
      raise Error, "Steps must start with a file, not an angle" unless @steps.first.is_a?(GcodeFile)
      raise Error, "Steps must end with a file, not an angle" unless @steps.last.is_a?(GcodeFile)
      angles.each do |angle|
        raise Error, "Angle #{angle} is negative — use a positive angle (0-360)" if angle.negative?
        raise Error, "Angle #{angle} is greater than 360 degrees" if angle > 360
      end
    end

    def angles
      @steps.select { |s| s.is_a?(Numeric) }
    end

    def header_comments(gcode_file)
      gcode_file.header.select { |line| line.strip.start_with?("(") }
    end

    def format_angle(angle)
      angle == angle.to_i ? angle.to_i.to_s : format("%.3f", angle)
    end
  end
end
