#!/bin/sh
#shellcheck disable=SC2004,SC2016

set -euf

: "${SHELLSPEC_SPEC_FAILURE_CODE:=101}"
: "${SHELLSPEC_FORMATTER:=debug}" "${SHELLSPEC_GENERATORS:=}"

interrupt=''
if (trap - INT) 2>/dev/null; then trap 'interrupt=1' INT; fi
if (trap - TERM) 2>/dev/null; then trap '' TERM; fi

echo $$ > "$SHELLSPEC_TMPBASE/$SHELLSPEC_REPORTER_PID"

# shellcheck source=lib/libexec/reporter.sh
. "${SHELLSPEC_LIB:-./lib}/libexec/reporter.sh"

import "formatter"
import "color_schema"
color_constants "${SHELLSPEC_COLOR:-}"

exit_status=0 found_focus='' no_examples='' aborted=1 coverage_failed=''
fail_fast='' fail_fast_count=${SHELLSPEC_FAIL_FAST_COUNT:-999999} reason=''
current_example_index=0 example_index=''
last_example_no='' last_skip_id='' not_enough_examples=''
field_id='' field_type='' field_tag='' field_example_no='' field_focused=''
field_temporary='' field_skipid='' field_pending='' field_message=''
field_quick='' field_trace='' field_lineno='' field_specfile=''

# shellcheck disable=SC2034
specfile_count=0 expected_example_count=0 example_count=0 \
succeeded_count='' failed_count='' warned_count='' \
todo_count='' fixed_count='' skipped_count='' \
suppressed_todo_count='' suppressed_fixed_count='' suppressed_skipped_count=''

init_quick_data

[ "$SHELLSPEC_GENERATORS" ] && mkdir -p "$SHELLSPEC_REPORTDIR"

load_formatter "$SHELLSPEC_FORMATTER" $SHELLSPEC_GENERATORS

formatters initialize "$@"
generators prepare "$@"

output_formatters begin

parse_lines() {
  buf=''
  while { IFS= read -r line || [ "$line" ]; } && [ ! "$fail_fast" ]; do
    case $line in
      $RS*) [ "$buf" ] && parse_fields "$buf"; buf=${line#?} ;;
      *) buf="$buf${buf:+$LF}${line}" ;;
    esac
  done
  [ ! "$buf" ] || parse_fields "$buf"
}

parse_fields() {
  OLDIFS=$IFS && IFS=$US && eval "set -- \$1" && IFS=$OLDIFS

  # Workaround: Do not merge two 'for'. A bug occurs in variable expansion
  # rarely in busybox-1.10.2.
  for field; do eval "field_${field%%:*}=\"\${field#*:}\""; done
  for field; do set -- "$@" "${field%%:*}" && shift; done

  each_line "$@"
}

each_line() {
  case $field_type in
    begin)
      field_example_count='' last_example_no=0
      last_skip_id='' suppress_pending=''
      inc specfile_count
      # shellcheck disable=SC2034
      example_count_per_file=0 succeeded_count_per_file=0 \
      failed_count_per_file=0 warned_count_per_file=0 todo_count_per_file=0 \
      fixed_count_per_file=0 skipped_count_per_file=0
      ;;
    example)
      # shellcheck disable=SC2034
      field_evaluation='' field_pending='' reason='' temporary_skip=0
      if [ "$field_example_no" -le "$last_example_no" ]; then
        abort "${LF}Illegal executed the same example" \
          "in ${field_specfile:-} line ${field_lineno_range:-}${LF}" \
          "(Did you execute in a loop?" \
          "Use 'parameterized example' if you want a loop)${LF}"
      fi
      [ "$field_focused" = "focus" ] && found_focus=1
      example_index='' last_example_no=$field_example_no
      eval "profiler_line$example_count=\$field_specfile:\$field_lineno_range"
      ;;
    statement)
      while :; do
        # Do not add references if example_index is blank
        case $field_tag in
          evaluation) break ;;
          good)
            [ "$field_pending" ] || break
            [ ! "$suppress_pending" ] || break
            ;;
          bad) [ ! "$suppress_pending" ] || break ;;
          pending)
            suppress_pending=1
            case $SHELLSPEC_PENDING_MESSAGE in (quiet)
              [ "$field_temporary" ] || break
            esac
            suppress_pending=''
            ;;
          skip)
            case $SHELLSPEC_SKIP_MESSAGE in (quiet)
              [ "$field_temporary" ] || break
            esac
            case $SHELLSPEC_SKIP_MESSAGE in (moderate|quiet)
              [ ! "$field_skipid" = "$last_skip_id" ] || break
              last_skip_id=$field_skipid
            esac
            inc temporary_skip
        esac

        # shellcheck disable=SC2034
        case $field_tag in (pending | skip)
          reason=$field_message
        esac

        if [ ! "$example_index" ]; then
          inc current_example_index
          example_index=$current_example_index
        fi
        break
      done
      ;;
    result)
      inc example_count example_count_per_file
      inc "${field_tag}_count" "${field_tag}_count_per_file"
      [ "${field_fail:-}" ] && exit_status=$SHELLSPEC_SPEC_FAILURE_CODE
      [ "${failed_count:-0}" -ge "$fail_fast_count" ] && aborted='' fail_fast=1

      case $field_tag in (skipped | fixed | todo)
        [ "$example_index" ] || inc "suppressed_${field_tag}_count"
      esac

      add_quick_data "$field_specfile:@$field_id" "$field_tag" "$field_quick"
      ;;
    end)
      # field_example_count not provided with range or filter
      : "${field_example_count:=$example_count_per_file}"
      expected_example_count=$(($expected_example_count + $field_example_count))
      if [ "$example_count_per_file" -ne "$field_example_count" ]; then
        not_enough_examples=${not_enough_examples:-0}
        not_enough_examples=$(($not_enough_examples + $field_example_count))
        not_enough_examples=$(($not_enough_examples - $example_count_per_file))
      fi
      ;;
    finished) aborted=''
  esac

  color_schema
  output_formatters each "$@"
  if [ "$field_type" = "result" ] && [ -e "$field_trace" ]; then
    output_trace < "$field_trace" >> "$SHELLSPEC_LOGFILE"
  fi
}
parse_lines

callback() { [ -e "$SHELLSPEC_TIME_LOG" ] || sleep 0; }
sequence callback 1 10
time_real=''
read_time_log "time" "$SHELLSPEC_TIME_LOG"

if [ -e "$SHELLSPEC_PROFILER_LOG" ]; then
  mkdir -p "$SHELLSPEC_REPORTDIR"
  sleep_wait [ ! -e "$SHELLSPEC_TMPBASE/profiler.done" ] ||:
  callback() { eval "putsn \"\$5\" \"\$profiler_line$3\""; }
  read -r profiler_tick_total < "${SHELLSPEC_PROFILER_LOG}.total"
  read_profiler callback "$profiler_tick_total" "$time_real" \
    < "$SHELLSPEC_PROFILER_LOG" \
    > "$SHELLSPEC_REPORTDIR/$SHELLSPEC_PROFILER_REPORT"
fi

output_formatters end

generators cleanup "$@"
formatters finalize "$@"

if [ "$aborted" ]; then
  exit_status=1
elif [ "$interrupt" ]; then
  exit_status=130
elif [ "${SHELLSPEC_FAIL_NO_EXAMPLES:-}" ] && [ "$example_count" -eq 0 ]; then
  #shellcheck disable=SC2034
  exit_status=$SHELLSPEC_SPEC_FAILURE_CODE no_examples=1
elif [ "$not_enough_examples" ]; then
  exit_status=$SHELLSPEC_SPEC_FAILURE_CODE
elif [ "$SHELLSPEC_FAIL_LOW_COVERAGE" ] && [ "$coverage_failed" ]; then
  exit_status=$SHELLSPEC_SPEC_FAILURE_CODE
fi

if [ "${SHELLSPEC_FOCUS_FILTER:-}" ]; then
  if [ ! "$found_focus" ]; then
    info "You specified --focus option, but not found any focused examples."
    info "To focus, prepend 'f' to groups / examples (e.g. fDescribe, fIt).$LF"
  fi
else
  if [ "$found_focus" ]; then
    info "You need to specify --focus option" \
      "to run focused (underlined) example(s) only.$LF"
  fi
fi

if [ -e "$SHELLSPEC_QUICK_FILE" ] && [ ! "$interrupt" ]; then
  quick_file="$SHELLSPEC_QUICK_FILE" done=1
  [ "${aborted}${not_enough_examples}${fail_fast}" ] && done=''
  [ -e "$quick_file" ] && in_quick_file=$quick_file || in_quick_file=/dev/null
  quick_file_data=$(filter_quick_file "$done" "$@" < "$in_quick_file")
  if [ -s "$quick_file" ] && [ ! "$quick_file_data" ]; then
    info "All examples have been passed. Rerun to prevent regression.$LF"
  fi
  puts "$quick_file_data${quick_file_data:+"$LF"}" | sort > "$quick_file"
fi

if [ -e "$SHELLSPEC_TMPBASE/$SHELLSPEC_DEPRECATION_LOGFILE" ]; then
  deprecated_count=0
  while IFS= read -r deprecated; do
    [ "$SHELLSPEC_DEPRECATION_LOG" ] && info "$deprecated"
    inc deprecated_count
  done < "$SHELLSPEC_TMPBASE/$SHELLSPEC_DEPRECATION_LOGFILE"
  deprecated="$deprecated_count deprecated syntax"
  [ "$deprecated_count" -ne 1 ] && deprecated="${deprecated}es"
  if [ "$SHELLSPEC_DEPRECATION_LOG" ]; then
    info "Found $deprecated. Please replace to the new syntax." \
      "It will be obsolete in the future."
    info "This message can be reduced with --hide-deprecations."
  else
    info "Found $deprecated. Show more details with --show-deprecations."
  fi
fi

exit "$exit_status"
