# frozen_string_literal: true

require "test_helper"

class TestCombiner < Minitest::Test
  include FixtureHelper

  def setup
    @roughing = Fission::GcodeFile.new(fixture_path("roughing.nc"))
    @finishing = Fission::GcodeFile.new(fixture_path("finishing.nc"))
    @third = Fission::GcodeFile.new(fixture_path("third_op.nc"))
  end

  # --- tool_change (files only, no rotations) ---

  def test_combine_includes_both_bodies
    result = Fission::Combiner.new([@roughing, @finishing]).combine
    assert_includes result, "T1 M6"
    assert_includes result, "T2 M6"
  end

  def test_combine_uses_first_header
    result = Fission::Combiner.new([@roughing, @finishing]).combine
    assert_includes result, "(roughing)"
  end

  def test_combine_has_single_m30
    result = Fission::Combiner.new([@roughing, @finishing]).combine
    assert_equal 1, result.scan(/^M30$/i).length
  end

  def test_combine_three_files
    result = Fission::Combiner.new([@roughing, @finishing, @third]).combine
    assert_includes result, "T1 M6"
    assert_includes result, "T2 M6"
    assert_includes result, "T3 M6"
    assert_equal 1, result.scan(/^M30$/i).length
  end

  def test_combine_includes_file_comments
    result = Fission::Combiner.new([@roughing, @finishing]).combine
    assert_includes result, "(--- Begin: roughing.nc ---)"
    assert_includes result, "(--- End: roughing.nc ---)"
    assert_includes result, "(--- Begin: finishing.nc ---)"
  end

  def test_combine_includes_header_comments_from_all_files
    result = Fission::Combiner.new([@roughing, @finishing, @third]).combine
    assert_includes result, "(roughing)"
    assert_includes result, "(finishing)"
    assert_includes result, "(third operation)"
  end

  # --- fourth_axis (files with rotation angles) ---

  def test_rotation_between_files
    result = Fission::Combiner.new([@roughing, 90, @finishing]).combine
    assert_includes result, "G0 A90"
    assert_includes result, "Rotate A-axis to 90 degrees"
  end

  def test_multiple_rotations
    result = Fission::Combiner.new([@roughing, 90, @finishing, 180, @third]).combine
    assert_includes result, "G0 A90"
    assert_includes result, "G0 A180"
  end

  def test_multiple_files_before_rotation
    result = Fission::Combiner.new([@roughing, @finishing, 90, @third]).combine
    assert_includes result, "T1 M6"
    assert_includes result, "T2 M6"
    assert_includes result, "G0 A90"
    assert_includes result, "T3 M6"
  end

  def test_multiple_files_after_rotation
    result = Fission::Combiner.new([@roughing, 90, @finishing, @third]).combine
    assert_includes result, "T1 M6"
    assert_includes result, "G0 A90"
    assert_includes result, "T2 M6"
    assert_includes result, "T3 M6"
  end

  def test_spindle_stop_before_rotation
    result = Fission::Combiner.new([@roughing, 90, @finishing]).combine
    lines = result.lines.map(&:strip)
    rotation_idx = lines.index { |l| l.include?("G0 A90") }
    m5_indices = lines.each_index.select { |i| lines[i] == "M5" }
    spindle_stop_idx = m5_indices.select { |i| i < rotation_idx }.last

    assert spindle_stop_idx, "Expected M5 before rotation"
    assert spindle_stop_idx < rotation_idx
  end

  def test_z_retract_before_rotation
    result = Fission::Combiner.new([@roughing, 45.5, @finishing]).combine
    assert_includes result, "G28 G91 Z0"
    assert_includes result, "G0 A45.500"
  end

  def test_integer_angle_formatting
    result = Fission::Combiner.new([@roughing, 90, @finishing]).combine
    assert_includes result, "G0 A90"
    refute_includes result, "G0 A90.000"
  end

  # --- validation ---

  def test_requires_at_least_two_files
    error = assert_raises(Fission::Error) do
      Fission::Combiner.new([@roughing])
    end
    assert_includes error.message, "At least two files"
  end

  def test_must_start_with_file
    error = assert_raises(Fission::Error) do
      Fission::Combiner.new([90, @roughing, @finishing])
    end
    assert_includes error.message, "start with a file"
  end

  def test_must_end_with_file
    error = assert_raises(Fission::Error) do
      Fission::Combiner.new([@roughing, @finishing, 90])
    end
    assert_includes error.message, "end with a file"
  end

  def test_negative_angle_is_error
    error = assert_raises(Fission::Error) do
      Fission::Combiner.new([@roughing, -90, @finishing])
    end
    assert_includes error.message, "negative"
  end

  def test_angle_over_360_is_error
    error = assert_raises(Fission::Error) do
      Fission::Combiner.new([@roughing, 361, @finishing])
    end
    assert_includes error.message, "greater than 360"
  end

  def test_angle_360_is_allowed
    result = Fission::Combiner.new([@roughing, 360, @finishing]).combine
    assert_includes result, "G0 A360"
  end

  def test_angle_0_is_allowed
    result = Fission::Combiner.new([@roughing, 0, @finishing]).combine
    assert_includes result, "G0 A0"
  end

  def test_consecutive_angles
    result = Fission::Combiner.new([@roughing, 90, 180, @finishing]).combine
    assert_includes result, "G0 A90"
    assert_includes result, "G0 A180"
  end

  # --- combined output validation ---

  def test_combined_output_with_rotation_validates
    combiner = Fission::Combiner.new([@roughing, 90, @finishing])
    combiner.combine
    validator = combiner.validate_combined
    assert validator.valid?, "Combined with rotation should validate but got errors: #{validator.errors.map(&:message).join(', ')}"
  end

  def test_validate_combined_before_combine_raises_runtime_error
    combiner = Fission::Combiner.new([@roughing, @finishing])
    assert_raises(RuntimeError) { combiner.validate_combined }
  end
end
