# frozen_string_literal: true

module Fission
  class Validator
    Result = Struct.new(:line_number, :line, :message, keyword_init: true)

    SUPPORTED_G_CODES = %w[
      G0 G1 G2 G3 G4
      G10
      G17 G18 G19
      G20 G21
      G28 G28.1 G30 G30.1
      G38.2 G38.3 G38.4 G38.5
      G40
      G43 G43.1 G49
      G53
      G54 G55 G56 G57 G58 G59
      G73 G80 G81 G82 G83
      G90 G91 G91.1
      G92 G92.1
      G93 G94
    ].freeze

    SUPPORTED_M_CODES = %w[
      M0 M1 M2 M3 M4 M5 M6 M7 M8 M9
      M10 M11
      M30
      M37 M40
      M48 M49
    ].freeze

    AXIS_WORDS = %w[X Y Z A].freeze
    ARC_PARAMS = %w[I J R].freeze

    attr_reader :errors, :warnings, :units, :tools

    def initialize(lines)
      @lines = lines
      @errors = []
      @warnings = []
      @spindle_on = false
      @tool_loaded = nil
      @feed_rate_set = false
      @air_on = false
      @air_warning_given = false
      @speed_set = false
      @units = nil
      @tools = []
      @last_comment = nil
      @last_tool_comment = nil
      validate
    end

    def valid?
      @errors.empty?
    end

    private

    def validate
      @lines.each_with_index do |raw_line, index|
        line_number = index + 1

        reset_state if raw_line.match?(/\A\(--- Begin: .+ ---\)\z/)

        # Track comments for tool descriptions (prefer Fusion-style "T1 D=..." comments)
        if (match = raw_line.match(/\A\s*\((.+)\)\s*\z/))
          comment = match[1]
          if comment.match?(/\AT\d/)
            @last_tool_comment = comment
          else
            @last_comment = comment
          end
        end

        line = strip_comments(raw_line).strip

        next if line.empty?
        next if line == "%"

        words = parse_words(line)

        if words.empty?
          add_error(line_number, raw_line, "Unrecognized content: #{line}")
          next
        end

        g_codes = extract_codes(words, "G")
        m_codes = extract_codes(words, "M")
        has_axis = words.any? { |w| AXIS_WORDS.include?(w[0]) }
        has_arc_param = words.any? { |w| ARC_PARAMS.include?(w[0]) }
        has_f = words.any? { |w| w[0] == "F" }
        has_s = words.any? { |w| w[0] == "S" }
        has_t = words.any? { |w| w[0] == "T" }
        t_value = extract_value(words, "T")

        # Track feed rate and speed from any line
        @feed_rate_set = true if has_f
        @speed_set = true if has_s

        # Track tool number from T word (even without M6 on same line)
        @pending_tool = t_value.to_i if has_t

        # Validate supported codes
        check_supported_g_codes(g_codes, line_number, raw_line)
        check_supported_m_codes(m_codes, line_number, raw_line)

        # Validate arguments
        check_motion_args(g_codes, has_axis, line_number, raw_line)
        check_arc_args(g_codes, has_arc_param, line_number, raw_line)
        check_dwell_args(g_codes, words, line_number, raw_line)
        check_spindle_speed(m_codes, has_s, line_number, raw_line)
        check_tool_change_args(m_codes, has_t, line_number, raw_line)

        # Stateful checks
        check_cutting_spindle(g_codes, line_number, raw_line)
        check_cutting_feed_rate(g_codes, line_number, raw_line)
        check_tool_before_spindle(m_codes, line_number, raw_line)
        check_spindle_during_tool_change(m_codes, line_number, raw_line)
        check_air_during_cutting(g_codes, line_number, raw_line)
        check_tool_atc_range(m_codes, line_number, raw_line)

        # Update state after checks
        update_state(g_codes, m_codes, has_t, t_value, line_number, raw_line)
      end
    end

    def strip_comments(line)
      line.gsub(/\([^)]*\)/, "").gsub(/;.*/, "")
    end

    def parse_words(line)
      line.scan(/([A-Z])(-?\d+\.?\d*)/i).map { |letter, num| [letter.upcase, num] }
    end

    def extract_codes(words, prefix)
      words.select { |w| w[0] == prefix }.map { |w| "#{prefix}#{w[1]}" }
    end

    def extract_value(words, letter)
      word = words.find { |w| w[0] == letter }
      word ? word[1] : nil
    end

    def cutting_codes?(g_codes)
      g_codes.any? { |c| %w[G1 G2 G3].include?(c) }
    end

    def motion_codes?(g_codes)
      g_codes.any? { |c| %w[G0 G1 G2 G3].include?(c) }
    end

    # --- Code support checks ---

    def check_supported_g_codes(g_codes, line_number, raw_line)
      g_codes.each do |code|
        unless SUPPORTED_G_CODES.include?(code)
          add_error(line_number, raw_line, "Unsupported G-code: #{code}")
        end
      end
    end

    def check_supported_m_codes(m_codes, line_number, raw_line)
      m_codes.each do |code|
        unless SUPPORTED_M_CODES.include?(code)
          add_error(line_number, raw_line, "Unsupported M-code: #{code}")
        end
      end
    end

    # --- Argument checks ---

    def check_motion_args(g_codes, has_axis, line_number, raw_line)
      %w[G0 G1].each do |code|
        if g_codes.include?(code) && !has_axis
          add_error(line_number, raw_line, "#{code} requires at least one axis word (X, Y, Z, or A)")
        end
      end
    end

    def check_arc_args(g_codes, has_arc_param, line_number, raw_line)
      %w[G2 G3].each do |code|
        if g_codes.include?(code) && !has_arc_param
          add_error(line_number, raw_line, "#{code} requires arc parameters (I/J or R)")
        end
      end
    end

    def check_dwell_args(g_codes, words, line_number, raw_line)
      if g_codes.include?("G4")
        has_p = words.any? { |w| w[0] == "P" }
        unless has_p
          add_error(line_number, raw_line, "G4 requires P parameter (dwell time)")
        end
      end
    end

    def check_spindle_speed(m_codes, has_s, line_number, raw_line)
      %w[M3 M4].each do |code|
        if m_codes.include?(code) && !has_s && !@speed_set
          add_error(line_number, raw_line, "#{code} requires S parameter (spindle speed)")
        end
      end
    end

    def check_tool_change_args(m_codes, has_t, line_number, raw_line)
      if m_codes.include?("M6") && !has_t && @pending_tool.nil?
        add_error(line_number, raw_line, "M6 requires T parameter (tool number)")
      end
    end

    # --- Stateful checks ---

    def check_cutting_spindle(g_codes, line_number, raw_line)
      if cutting_codes?(g_codes) && !@spindle_on
        add_error(line_number, raw_line, "Cutting move with spindle off")
      end
    end

    def check_cutting_feed_rate(g_codes, line_number, raw_line)
      if cutting_codes?(g_codes) && !@feed_rate_set
        add_error(line_number, raw_line, "Cutting move without feed rate set")
      end
    end

    def check_tool_before_spindle(m_codes, line_number, raw_line)
      if (m_codes.include?("M3") || m_codes.include?("M4")) && @tool_loaded.nil?
        add_warning(line_number, raw_line, "Spindle start without prior tool change")
      end
    end

    def check_spindle_during_tool_change(m_codes, line_number, raw_line)
      if m_codes.include?("M6") && @spindle_on
        add_error(line_number, raw_line, "Tool change while spindle is running")
      end
    end

    def check_air_during_cutting(g_codes, line_number, raw_line)
      if cutting_codes?(g_codes) && !@air_on && !@air_warning_given
        add_warning(line_number, raw_line, "Cutting move without air blast on")
        @air_warning_given = true
      end
    end

    def check_tool_atc_range(m_codes, line_number, raw_line)
      if m_codes.include?("M6") && @pending_tool && @pending_tool > 6
        add_warning(line_number, raw_line, "Tool T#{@pending_tool} is outside ATC range (1-6), requires manual tool change")
      end
    end

    # --- State updates ---

    def update_state(g_codes, m_codes, has_t, t_value, line_number, raw_line)
      if g_codes.include?("G21")
        if @units && @units != "mm"
          add_warning(line_number, raw_line, "Mixed units: switching from #{@units} to mm")
        end
        @units ||= "mm"
      end
      if g_codes.include?("G20")
        if @units && @units != "in"
          add_warning(line_number, raw_line, "Mixed units: switching from #{@units} to in")
        end
        @units ||= "in"
      end

      if m_codes.include?("M3") || m_codes.include?("M4")
        @spindle_on = true
      end

      if m_codes.include?("M5") || m_codes.include?("M2") || m_codes.include?("M30")
        @spindle_on = false
      end

      if m_codes.include?("M6")
        tool_num = @pending_tool || @tool_loaded
        if tool_num && @tools.none? { |t| t[:number] == tool_num }
          @tools << { number: tool_num, description: @last_tool_comment }
        end
        @tool_loaded = @pending_tool || @tool_loaded
        @pending_tool = nil
      end

      @last_comment = nil if has_t || m_codes.any?
      @last_tool_comment = nil if m_codes.include?("M6")

      @air_on = true if m_codes.include?("M7") || m_codes.include?("M8")
      @air_on = false if m_codes.include?("M9")
    end

    def reset_state
      @spindle_on = false
      @tool_loaded = nil
      @pending_tool = nil
      @feed_rate_set = false
      @air_on = false
      @air_warning_given = false
      @speed_set = false
    end

    def add_error(line_number, line, message)
      @errors << Result.new(line_number: line_number, line: line.strip, message: message)
    end

    def add_warning(line_number, line, message)
      @warnings << Result.new(line_number: line_number, line: line.strip, message: message)
    end
  end
end
