# frozen_string_literal: true

require "test_helper"

class TestGcodeFile < Minitest::Test
  include FixtureHelper

  def setup
    @file = Fission::GcodeFile.new(fixture_path("roughing.nc"))
  end

  def test_parses_header
    assert_includes @file.header.join("\n"), "G90 G94"
    assert_includes @file.header.join("\n"), "G17"
    assert_includes @file.header.join("\n"), "G21"
  end

  def test_header_does_not_include_tool_call
    refute @file.header.any? { |l| l.include?("T1") }
  end

  def test_parses_body
    body_text = @file.body.join("\n")
    assert_includes body_text, "T1 M6"
    assert_includes body_text, "G1 X50 F1000"
  end

  def test_body_does_not_include_m30
    refute @file.body.any? { |l| l.strip.match?(/\AM30\b/i) }
  end

  def test_parses_footer
    footer_text = @file.footer.join("\n")
    assert_includes footer_text, "M30"
  end

  def test_filename
    assert_equal "roughing.nc", @file.filename
  end

  def test_empty_file
    Dir.mktmpdir do |dir|
      path = File.join(dir, "empty.nc")
      File.write(path, "")
      file = Fission::GcodeFile.new(path)
      assert_equal [], file.header
      assert_equal [], file.body
      assert_equal [], file.footer
    end
  end

  def test_comment_only_file
    Dir.mktmpdir do |dir|
      path = File.join(dir, "comments.nc")
      File.write(path, "(just a comment)\n")
      file = Fission::GcodeFile.new(path)
      assert_equal ["(just a comment)"], file.header
      assert_equal [], file.body
      assert_equal [], file.footer
    end
  end
end
