#shellcheck shell=sh

% FILE: "$SHELLSPEC_SPECDIR/fixture/end-with-multiple-lf.txt"

Describe "core/modifiers/contents.sh"
  BeforeRun set_subject modifier_mock

  Describe "contents modifier"
    Example 'example'
      The contents of file "$FILE" should equal "a"
      The contents of the file "$FILE" should equal "a"
      The file "$FILE" contents should equal "a"
    End

    It 'reads the contents of the file when file exists'
      subject() { %- "$FILE"; }
      When run shellspec_modifier_contents _modifier_
      The entire stdout should equal "a"
    End

    It 'can not reads the contents of the file when file not exists'
      subject() { %- "$FILE.not-exists"; }
      When run shellspec_modifier_contents _modifier_
      The status should be failure
    End

    It 'can not reads the contents of the file when file not specified'
      subject() { false; }
      When run shellspec_modifier_contents _modifier_
      The status should be failure
    End

    It 'outputs error if next modifier is missing'
      subject() { %- "$FILE"; }
      When run shellspec_modifier_contents
      The entire stderr should equal SYNTAX_ERROR_DISPATCH_FAILED
    End
  End

  Describe "entire contents modifier"
    Example 'example'
      The entire contents of file "$FILE" should equal "a${LF}${LF}"
      The entire contents of the file "$FILE" should equal "a${LF}${LF}"
      The file "$FILE" entire contents should equal "a${LF}${LF}"
    End

    It 'reads the entire contents of the file when file exists'
      subject() { %- "$FILE"; }
      When run shellspec_modifier_entire_contents _modifier_
      The entire stdout should equal "a${LF}${LF}"
    End

    It 'can not reads the entire contents of the file when file not exists'
      subject() { %- "$FILE.not-exists"; }
      When run shellspec_modifier_entire_contents _modifier_
      The status should be failure
    End

    It 'can not read the entire contents of the file when file not specified'
      subject() { false; }
      When run shellspec_modifier_entire_contents _modifier_
      The status should be failure
    End

    It 'outputs error if next modifier is missing'
      subject() { %- "$FILE"; }
      When run shellspec_modifier_entire_contents
      The entire stderr should equal SYNTAX_ERROR_DISPATCH_FAILED
    End
  End
End
