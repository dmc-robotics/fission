# frozen_string_literal: true

require "test_helper"

class TestCLI < Minitest::Test
  include FixtureHelper

  def test_help_flag
    out, = capture_io { @status = Fission::CLI.new(["--help"]).run }
    assert_equal 0, @status
    assert_includes out, "Usage:"
    assert_includes out, "combine"
  end

  def test_version_flag
    out, = capture_io { @status = Fission::CLI.new(["--version"]).run }
    assert_equal 0, @status
    assert_includes out, Fission::VERSION
  end

  def test_no_args_shows_help
    out, = capture_io { @status = Fission::CLI.new([]).run }
    assert_equal 0, @status
    assert_includes out, "Usage:"
  end

  def test_unknown_command
    _, err = capture_io { @status = Fission::CLI.new(["bogus"]).run }
    assert_equal 1, @status
    assert_includes err, "Unknown command"
  end

  def test_combine_to_stdout
    out, = capture_io do
      @status = Fission::CLI.new([
        "combine",
        fixture_path("roughing.nc"),
        fixture_path("finishing.nc")
      ]).run
    end
    assert_equal 0, @status
    assert_includes out, "T1 M6"
    assert_includes out, "T2 M6"
  end

  def test_combine_to_file
    Dir.mktmpdir do |dir|
      output = File.join(dir, "out.nc")
      _, err = capture_io do
        @status = Fission::CLI.new([
          "combine",
          "-o", output,
          fixture_path("roughing.nc"),
          fixture_path("finishing.nc")
        ]).run
      end
      assert_equal 0, @status
      assert File.exist?(output)
      content = File.read(output)
      assert_includes content, "T1 M6"
      assert_includes content, "T2 M6"
      assert_includes err, "Wrote #{output}"
    end
  end

  def test_combine_requires_two_files
    _, err = capture_io do
      @status = Fission::CLI.new([
        "combine",
        fixture_path("roughing.nc")
      ]).run
    end
    assert_equal 1, @status
    assert_includes err, "at least two files"
  end

  def test_combine_with_rotation
    out, = capture_io do
      @status = Fission::CLI.new([
        "combine",
        fixture_path("roughing.nc"),
        "90",
        fixture_path("finishing.nc")
      ]).run
    end
    assert_equal 0, @status
    assert_includes out, "G0 A90"
  end

  def test_combine_multiple_files_between_angles
    out, = capture_io do
      @status = Fission::CLI.new([
        "combine",
        fixture_path("roughing.nc"),
        fixture_path("finishing.nc"),
        "90",
        fixture_path("third_op.nc")
      ]).run
    end
    assert_equal 0, @status
    assert_includes out, "T1 M6"
    assert_includes out, "T2 M6"
    assert_includes out, "G0 A90"
    assert_includes out, "T3 M6"
  end

  def test_combine_multiple_angles
    out, = capture_io do
      @status = Fission::CLI.new([
        "combine",
        fixture_path("roughing.nc"),
        "90",
        fixture_path("finishing.nc"),
        "180",
        fixture_path("third_op.nc")
      ]).run
    end
    assert_equal 0, @status
    assert_includes out, "G0 A90"
    assert_includes out, "G0 A180"
  end

  def test_missing_file
    _, err = capture_io do
      @status = Fission::CLI.new([
        "combine",
        "nonexistent1.nc",
        "nonexistent2.nc"
      ]).run
    end
    assert_equal 1, @status
    assert_includes err, "Error:"
  end

  # --- validate command ---

  def test_validate_clean_file
    capture_io do
      @status = Fission::CLI.new([
        "validate",
        fixture_path("roughing.nc")
      ]).run
    end
    assert_equal 0, @status
  end

  def test_validate_multiple_files
    capture_io do
      @status = Fission::CLI.new([
        "validate",
        fixture_path("roughing.nc"),
        fixture_path("finishing.nc")
      ]).run
    end
    assert_equal 0, @status
  end

  def test_validate_no_args
    _, err = capture_io do
      @status = Fission::CLI.new(["validate"]).run
    end
    assert_equal 1, @status
    assert_includes err, "at least one file"
  end

  def test_validate_reports_errors
    Dir.mktmpdir do |dir|
      bad_file = File.join(dir, "bad.nc")
      File.write(bad_file, "G99 X10\n")
      _, err = capture_io do
        @status = Fission::CLI.new(["validate", bad_file]).run
      end
      assert_equal 1, @status
      assert_includes err, "Unsupported G-code"
    end
  end

  # --- --output long form ---

  def test_combine_with_long_output_option
    Dir.mktmpdir do |dir|
      output = File.join(dir, "out.nc")
      capture_io do
        @status = Fission::CLI.new([
          "combine",
          "--output", output,
          fixture_path("roughing.nc"),
          fixture_path("finishing.nc")
        ]).run
      end
      assert_equal 0, @status
      assert File.exist?(output)
      assert_includes File.read(output), "T1 M6"
    end
  end

  # --- unknown flags ---

  def test_unknown_flag_is_error
    _, err = capture_io do
      @status = Fission::CLI.new([
        "combine",
        fixture_path("roughing.nc"),
        "-f",
        fixture_path("finishing.nc")
      ]).run
    end
    assert_equal 1, @status
    assert_includes err, "Unknown option"
  end

  # --- codes command ---

  def test_codes_command
    out, = capture_io { @status = Fission::CLI.new(["codes"]).run }
    assert_equal 0, @status
    assert_includes out, "Supported Carvera G-codes"
    assert_includes out, "Supported Carvera M-codes"
    assert_includes out, "G0"
    assert_includes out, "M6"
  end

  # --- missing -o filename ---

  def test_combine_missing_output_filename
    _, err = capture_io do
      @status = Fission::CLI.new([
        "combine",
        "-o"
      ]).run
    end
    assert_equal 1, @status
    assert_includes err, "Missing output filename"
  end

  # --- combine with only one file and an angle ---

  def test_combine_one_file_and_angle
    _, err = capture_io do
      @status = Fission::CLI.new([
        "combine",
        fixture_path("roughing.nc"),
        "90"
      ]).run
    end
    assert_equal 1, @status
    assert_includes err, "at least two files"
  end

  # --- validate prints summary on success ---

  def test_validate_prints_summary
    _, err = capture_io do
      @status = Fission::CLI.new([
        "validate",
        fixture_path("roughing.nc")
      ]).run
    end
    assert_equal 0, @status
    assert_includes err, "roughing.nc: ok"
    assert_includes err, "Units:"
    assert_includes err, "T1"
  end
end
