# frozen_string_literal: true

require "test_helper"

class TestValidator < Minitest::Test
  include FixtureHelper

  # Helper to validate an array of G-code lines
  def validate(lines)
    Fission::Validator.new(lines)
  end

  # --- Unsupported codes ---

  def test_unsupported_g_code_is_error
    v = validate(["G99 X10"])
    assert_equal 1, v.errors.size
    assert_match(/Unsupported G-code: G99/, v.errors.first.message)
  end

  def test_unsupported_m_code_is_error
    v = validate(["M50"])
    assert_equal 1, v.errors.size
    assert_match(/Unsupported M-code: M50/, v.errors.first.message)
  end

  def test_supported_g_codes_pass_clean
    # Test a representative set of supported G-codes (with required args)
    lines = [
      "G17",
      "G21",
      "G90 G94",
      "G54",
      "G28 G91 Z0",
    ]
    v = validate(lines)
    supported_errors = v.errors.select { |e| e.message.include?("Unsupported") }
    assert_empty supported_errors
  end

  def test_supported_m_codes_pass_clean
    lines = [
      "T1 M6",
      "S10000 M3",
      "M7",
      "M5",
      "M9",
      "M30",
    ]
    v = validate(lines)
    supported_errors = v.errors.select { |e| e.message.include?("Unsupported") }
    assert_empty supported_errors
  end

  # --- G0/G1 missing axis word ---

  def test_g0_missing_axis_is_error
    v = validate(["G0"])
    errors = v.errors.select { |e| e.message.include?("G0 requires") }
    assert_equal 1, errors.size
  end

  def test_g0_with_axis_is_clean
    v = validate(["G0 X10"])
    errors = v.errors.select { |e| e.message.include?("G0 requires") }
    assert_empty errors
  end

  def test_g0_with_z_axis_is_clean
    v = validate(["G0 Z15"])
    errors = v.errors.select { |e| e.message.include?("G0 requires") }
    assert_empty errors
  end

  def test_g0_with_a_axis_is_clean
    v = validate(["G0 A90"])
    errors = v.errors.select { |e| e.message.include?("G0 requires") }
    assert_empty errors
  end

  def test_g1_missing_axis_is_error
    v = validate(["T1 M6", "S10000 M3", "M7", "G1 F500"])
    errors = v.errors.select { |e| e.message.include?("G1 requires") }
    assert_equal 1, errors.size
  end

  def test_g1_with_axis_is_clean
    v = validate(["T1 M6", "S10000 M3", "M7", "G1 X10 F500"])
    errors = v.errors.select { |e| e.message.include?("G1 requires") }
    assert_empty errors
  end

  # --- G2/G3 missing arc params ---

  def test_g2_missing_arc_params_is_error
    v = validate(["T1 M6", "S10000 M3", "M7", "G1 X0 F500", "G2 X10 Y10"])
    errors = v.errors.select { |e| e.message.include?("G2 requires arc") }
    assert_equal 1, errors.size
  end

  def test_g2_with_ij_is_clean
    v = validate(["T1 M6", "S10000 M3", "M7", "G1 X0 F500", "G2 X10 Y10 I5 J5"])
    errors = v.errors.select { |e| e.message.include?("G2 requires arc") }
    assert_empty errors
  end

  def test_g2_with_r_is_clean
    v = validate(["T1 M6", "S10000 M3", "M7", "G1 X0 F500", "G2 X10 Y10 R5"])
    errors = v.errors.select { |e| e.message.include?("G2 requires arc") }
    assert_empty errors
  end

  def test_g3_missing_arc_params_is_error
    v = validate(["T1 M6", "S10000 M3", "M7", "G1 X0 F500", "G3 X10 Y10"])
    errors = v.errors.select { |e| e.message.include?("G3 requires arc") }
    assert_equal 1, errors.size
  end

  def test_g3_with_ij_is_clean
    v = validate(["T1 M6", "S10000 M3", "M7", "G1 X0 F500", "G3 X10 Y10 I5 J0"])
    errors = v.errors.select { |e| e.message.include?("G3 requires arc") }
    assert_empty errors
  end

  # --- G4 missing P ---

  def test_g4_missing_p_is_error
    v = validate(["G4"])
    errors = v.errors.select { |e| e.message.include?("G4 requires P") }
    assert_equal 1, errors.size
  end

  def test_g4_with_p_is_clean
    v = validate(["G4 P100"])
    errors = v.errors.select { |e| e.message.include?("G4 requires P") }
    assert_empty errors
  end

  # --- M3/M4 missing S ---

  def test_m3_missing_s_is_error
    v = validate(["T1 M6", "M3"])
    errors = v.errors.select { |e| e.message.include?("M3 requires S") }
    assert_equal 1, errors.size
  end

  def test_m3_with_s_on_same_line_is_clean
    v = validate(["T1 M6", "S10000 M3"])
    errors = v.errors.select { |e| e.message.include?("M3 requires S") }
    assert_empty errors
  end

  def test_m3_with_s_on_prior_line_is_clean
    v = validate(["T1 M6", "S10000", "M3"])
    errors = v.errors.select { |e| e.message.include?("M3 requires S") }
    assert_empty errors
  end

  def test_m4_missing_s_is_error
    v = validate(["T1 M6", "M4"])
    errors = v.errors.select { |e| e.message.include?("M4 requires S") }
    assert_equal 1, errors.size
  end

  # --- M6 missing T ---

  def test_m6_missing_t_is_error
    v = validate(["M6"])
    errors = v.errors.select { |e| e.message.include?("M6 requires T") }
    assert_equal 1, errors.size
  end

  def test_m6_with_t_on_same_line_is_clean
    v = validate(["T1 M6"])
    errors = v.errors.select { |e| e.message.include?("M6 requires T") }
    assert_empty errors
  end

  def test_m6_with_t_on_prior_line_is_clean
    v = validate(["T1", "M6"])
    errors = v.errors.select { |e| e.message.include?("M6 requires T") }
    assert_empty errors
  end

  # --- Cutting with spindle off (error) ---

  def test_cutting_with_spindle_off_is_error
    v = validate(["T1 M6", "M7", "G1 X10 F500"])
    errors = v.errors.select { |e| e.message.include?("spindle off") }
    assert_equal 1, errors.size
  end

  def test_cutting_after_spindle_start_is_clean
    v = validate(["T1 M6", "S10000 M3", "M7", "G1 X10 F500"])
    errors = v.errors.select { |e| e.message.include?("spindle off") }
    assert_empty errors
  end

  def test_cutting_after_spindle_stop_is_error
    v = validate(["T1 M6", "S10000 M3", "M7", "G1 X10 F500", "M5", "G1 X20 F500"])
    errors = v.errors.select { |e| e.message.include?("spindle off") }
    assert_equal 1, errors.size
  end

  def test_g2_with_spindle_off_is_error
    v = validate(["T1 M6", "M7", "G2 X10 Y10 I5 J5 F500"])
    errors = v.errors.select { |e| e.message.include?("spindle off") }
    assert_equal 1, errors.size
  end

  def test_g3_with_spindle_off_is_error
    v = validate(["T1 M6", "M7", "G3 X10 Y10 I5 J0 F500"])
    errors = v.errors.select { |e| e.message.include?("spindle off") }
    assert_equal 1, errors.size
  end

  def test_g0_with_spindle_off_is_not_error
    # G0 is rapid move, not cutting — should not trigger spindle check
    v = validate(["G0 X10"])
    errors = v.errors.select { |e| e.message.include?("spindle off") }
    assert_empty errors
  end

  # --- No feed rate before cut (error) ---

  def test_cutting_without_feed_rate_is_error
    v = validate(["T1 M6", "S10000 M3", "M7", "G1 X10"])
    errors = v.errors.select { |e| e.message.include?("feed rate") }
    assert_equal 1, errors.size
  end

  def test_cutting_with_feed_rate_is_clean
    v = validate(["T1 M6", "S10000 M3", "M7", "G1 X10 F500"])
    errors = v.errors.select { |e| e.message.include?("feed rate") }
    assert_empty errors
  end

  def test_cutting_with_prior_feed_rate_is_clean
    v = validate(["T1 M6", "S10000 M3", "M7", "G0 X0 F500", "G1 X10"])
    errors = v.errors.select { |e| e.message.include?("feed rate") }
    assert_empty errors
  end

  # --- No tool before spindle start (warning) ---

  def test_spindle_without_tool_is_warning
    v = validate(["S10000 M3"])
    warnings = v.warnings.select { |w| w.message.include?("without prior tool") }
    assert_equal 1, warnings.size
  end

  def test_spindle_with_tool_is_clean
    v = validate(["T1 M6", "S10000 M3"])
    warnings = v.warnings.select { |w| w.message.include?("without prior tool") }
    assert_empty warnings
  end

  def test_m4_without_tool_is_warning
    v = validate(["S10000 M4"])
    warnings = v.warnings.select { |w| w.message.include?("without prior tool") }
    assert_equal 1, warnings.size
  end

  # --- Spindle on during tool change (error) ---

  def test_tool_change_with_spindle_on_is_error
    v = validate(["T1 M6", "S10000 M3", "T2 M6"])
    errors = v.errors.select { |e| e.message.include?("spindle is running") }
    assert_equal 1, errors.size
  end

  def test_tool_change_after_spindle_stop_is_clean
    v = validate(["T1 M6", "S10000 M3", "M5", "T2 M6"])
    errors = v.errors.select { |e| e.message.include?("spindle is running") }
    assert_empty errors
  end

  # --- Air not on during cutting (warning) ---

  def test_cutting_without_air_is_warning
    v = validate(["T1 M6", "S10000 M3", "G1 X10 F500"])
    warnings = v.warnings.select { |w| w.message.include?("air blast") }
    assert_equal 1, warnings.size
  end

  def test_cutting_with_air_is_clean
    v = validate(["T1 M6", "S10000 M3", "M7", "G1 X10 F500"])
    warnings = v.warnings.select { |w| w.message.include?("air blast") }
    assert_empty warnings
  end

  def test_cutting_after_air_off_is_warning
    v = validate(["T1 M6", "S10000 M3", "M7", "G1 X10 F500", "M9", "G1 X20"])
    warnings = v.warnings.select { |w| w.message.include?("air blast") }
    assert_equal 1, warnings.size
  end

  # --- Tool number outside ATC range (warning) ---

  def test_tool_outside_atc_range_is_warning
    v = validate(["T7 M6"])
    warnings = v.warnings.select { |w| w.message.include?("ATC range") }
    assert_equal 1, warnings.size
  end

  def test_tool_inside_atc_range_is_clean
    v = validate(["T1 M6"])
    warnings = v.warnings.select { |w| w.message.include?("ATC range") }
    assert_empty warnings
  end

  def test_tool_6_is_clean
    v = validate(["T6 M6"])
    warnings = v.warnings.select { |w| w.message.include?("ATC range") }
    assert_empty warnings
  end

  def test_tool_99_is_warning
    v = validate(["T99 M6"])
    warnings = v.warnings.select { |w| w.message.include?("ATC range") }
    assert_equal 1, warnings.size
    assert_match(/T99/, warnings.first.message)
  end

  # --- State reset ---

  def test_m5_clears_spindle_state
    v = validate(["T1 M6", "S10000 M3", "M7", "G1 X10 F500", "M5", "G1 X20"])
    errors = v.errors.select { |e| e.message.include?("spindle off") }
    assert_equal 1, errors.size
    assert_equal 6, errors.first.line_number
  end

  def test_m9_clears_air_state
    v = validate(["T1 M6", "S10000 M3", "M7", "G1 X10 F500", "M9", "G1 X20"])
    warnings = v.warnings.select { |w| w.message.include?("air blast") }
    assert_equal 1, warnings.size
    assert_equal 6, warnings.first.line_number
  end

  def test_m30_resets_spindle_state
    v = validate(["T1 M6", "S10000 M3", "M7", "G1 X10 F500", "M30", "G1 X20"])
    errors = v.errors.select { |e| e.message.include?("spindle off") }
    assert_equal 1, errors.size
  end

  def test_m2_resets_spindle_state
    v = validate(["T1 M6", "S10000 M3", "M7", "G1 X10 F500", "M2", "G1 X20"])
    errors = v.errors.select { |e| e.message.include?("spindle off") }
    assert_equal 1, errors.size
  end

  # --- Multi-code lines ---

  def test_multiple_g_codes_on_one_line
    v = validate(["G90 G94"])
    assert v.valid?, "G90 G94 should be valid"
  end

  def test_t_and_m6_on_same_line
    v = validate(["T1 M6"])
    errors = v.errors.select { |e| e.message.include?("M6 requires T") }
    assert_empty errors
  end

  def test_s_and_m3_on_same_line
    v = validate(["T1 M6", "S10000 M3"])
    errors = v.errors.select { |e| e.message.include?("requires S") }
    assert_empty errors
  end

  # --- Unrecognized content ---

  def test_gibberish_text_is_error
    v = validate(["hello world"])
    assert_equal 1, v.errors.size
    assert_match(/Unrecognized content/, v.errors.first.message)
  end

  def test_percent_delimiter_is_valid
    v = validate(["%"])
    assert v.valid?
  end

  # --- Comments ---

  def test_comments_are_ignored
    v = validate(["(this is a comment)"])
    assert v.valid?
  end

  def test_inline_comments_stripped
    v = validate(["G0 X10 (move to start)"])
    errors = v.errors.select { |e| e.message.include?("Unsupported") }
    assert_empty errors
  end

  # --- Blank lines ---

  def test_blank_lines_are_skipped
    v = validate(["", "  ", ""])
    assert v.valid?
  end

  # --- Line numbers in results ---

  def test_error_includes_correct_line_number
    v = validate(["G17", "G21", "G99 X10"])
    assert_equal 3, v.errors.first.line_number
  end

  def test_error_includes_line_content
    v = validate(["G99 X10"])
    assert_equal "G99 X10", v.errors.first.line
  end

  # --- valid? method ---

  def test_valid_with_no_errors
    v = validate(["G17", "G21"])
    assert v.valid?
  end

  def test_invalid_with_errors
    v = validate(["G99 X10"])
    refute v.valid?
  end

  def test_valid_with_only_warnings
    # Spindle start without tool is a warning, not error
    v = validate(["S10000 M3"])
    # Check that there are warnings but still valid (no errors from unsupported codes)
    warnings = v.warnings.select { |w| w.message.include?("without prior tool") }
    refute_empty warnings
  end

  # --- Mixed units ---

  def test_mixed_units_is_warning
    v = validate(["G21", "G17", "G20"])
    warnings = v.warnings.select { |w| w.message.include?("Mixed units") }
    assert_equal 1, warnings.size
    assert_match(/mm to in/, warnings.first.message)
  end

  def test_same_units_repeated_is_clean
    v = validate(["G21", "G17", "G21"])
    warnings = v.warnings.select { |w| w.message.include?("Mixed units") }
    assert_empty warnings
  end

  def test_units_tracking
    v = validate(["G21"])
    assert_equal "mm", v.units

    v = validate(["G20"])
    assert_equal "in", v.units
  end

  # --- Tool tracking ---

  def test_tools_tracked
    v = validate(["T1 M6", "S10000 M3", "M5", "T2 M6"])
    assert_equal 2, v.tools.size
    assert_equal 1, v.tools[0][:number]
    assert_equal 2, v.tools[1][:number]
  end

  # --- Integration: fixture files validate clean ---

  def test_roughing_fixture_validates_clean
    file = Fission::GcodeFile.new(fixture_path("roughing.nc"))
    assert file.valid?, "roughing.nc should validate clean but got errors: #{file.validation_errors.map(&:message).join(', ')}"
  end

  def test_finishing_fixture_validates_clean
    file = Fission::GcodeFile.new(fixture_path("finishing.nc"))
    assert file.valid?, "finishing.nc should validate clean but got errors: #{file.validation_errors.map(&:message).join(', ')}"
  end

  def test_third_op_fixture_validates_clean
    file = Fission::GcodeFile.new(fixture_path("third_op.nc"))
    assert file.valid?, "third_op.nc should validate clean but got errors: #{file.validation_errors.map(&:message).join(', ')}"
  end

  # --- Integration: combined output validates ---

  def test_combined_output_validates
    files = [
      Fission::GcodeFile.new(fixture_path("roughing.nc")),
      Fission::GcodeFile.new(fixture_path("finishing.nc")),
    ]
    combiner = Fission::Combiner.new(files)
    combiner.combine
    validator = combiner.validate_combined
    assert validator.valid?, "Combined output should validate but got errors: #{validator.errors.map(&:message).join(', ')}"
  end
end
