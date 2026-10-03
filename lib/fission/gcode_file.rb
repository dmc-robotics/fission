# frozen_string_literal: true

module Fission
  # Parses a Fusion 360 G-code file and separates it into header, body, and footer.
  #
  # Fusion 360's Carvera post processor generates files with a recognizable structure:
  # - Header: initial setup (G-code modes, units, coordinate system)
  # - Body: the actual cutting operations
  # - Footer: spindle stop, retract, program end (M30/M2/%)
  class GcodeFile
    attr_reader :path, :lines, :header, :body, :footer,
                :validation_errors, :validation_warnings, :validator

    # Lines that mark the end of the cutting program
    FOOTER_PATTERNS = [
      /\AM30\b/i,  # program end
      /\AM2\b/i,   # program end
      /\A%\s*\z/,  # program delimiter
    ].freeze

    # Lines that are part of the startup sequence (before cutting begins)
    HEADER_PATTERNS = [
      /\A[%()]/,         # program delimiter or comments
      /\AG17\b/i,        # XY plane selection
      /\AG21\b/i,        # metric units
      /\AG20\b/i,        # imperial units
      /\AG90\b/i,        # absolute positioning
      /\AG91\b/i,        # incremental positioning
      /\AG28\b/i,        # return to home
      /\AG92\b/i,        # coordinate system offset
      /\AG94\b/i,        # feed per minute mode
    ].freeze

    def initialize(path)
      @path = path
      @lines = File.readlines(path, chomp: true)
      parse
      run_validation
    end

    def filename
      File.basename(@path)
    end

    def valid?
      @validation_errors.empty?
    end

    private

    def parse
      @header = []
      @body = []
      @footer = []

      in_header = true
      in_footer = false

      @lines.each do |line|
        stripped = line.strip

        # Skip blank lines in header/footer detection
        if stripped.empty?
          if in_footer
            @footer << line
          elsif in_header
            @header << line
          else
            @body << line
          end
          next
        end

        if in_footer
          @footer << line
          next
        end

        if !in_header && footer_line?(stripped)
          in_footer = true
          @footer << line
          next
        end

        if in_header
          # The first tool call or spindle start marks the transition from header to body
          if stripped.match?(/\A[TM]/) && stripped.match?(/\b(T\d|M[356])\b/i)
            in_header = false
            @body << line
          elsif header_line?(stripped)
            @header << line
          else
            in_header = false
            @body << line
          end
        else
          @body << line
        end
      end
    end

    def run_validation
      @validator = Validator.new(@lines)
      @validation_errors = @validator.errors
      @validation_warnings = @validator.warnings
    end

    def footer_line?(line)
      FOOTER_PATTERNS.any? { |p| line.match?(p) }
    end

    def header_line?(line)
      HEADER_PATTERNS.any? { |p| line.match?(p) }
    end
  end
end
