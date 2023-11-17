#!/usr/bin/env bash

###############################################################################
# progpipe: A bash script for real-time progress estimation in data streams.
# It calculates and displays estimated completion time (ETC) for jobs based on
# piped input. Useful for long-running tasks or people who need to wait. Often.
# 
# Writen by Nathaniel Evry - nathaniel.evry@gmail.com
# https://github.com/altometer/progpipe
################################################################################

show_help() {
	# Help information is printed and the script exits after displaying.
	# Print detailed usage instructions, available options and flags,
	# and several examples to demonstrate how to use the script.

	cat <<EOFHELP
progpipe does ETC calculations on incrementing or decrementing piped input

Usage: (your program) | progpipe {goal_number} OR [option(s)]

-h, --help	Show this help printout
-g, --goal-num	Set the goal number [0 or larger] DEFAULT:{argument pos 1}
-f, --field-sel	Designate a tab seperated column from the input
-d, --debug	Print all internal variables declared in main every draw loop
-t, --test-mode	Perform some automated count-up and count-down tests on a loop
-c, --no-clear	Do not clear the screen when updating
-m, --message	Add a header to the progpipe draw loop
-v, --verbose	Print extended ETC as days/hours/mins/secs [See examples]

#### Examples ####

$ (stream) | progpipe 100
$ (stream) | progpipe -g 100
$ (stream) | progpipe -g 0 -f 3 -m "File Download" --verbose

# -f, --field-sel mode will awk print the desired value
$ (stream	desiredValue) | progpipe -g 100 -f2

# Create a test data stream
$ for i in {1..101};do
echo "$i";sleep 0.25
done | progpipe 101
> [ 47.5247% 48/101 ]     avg/s:4.0000    etc:2022-06-02 14:38:40

$ (stream) | progpipe -g 600 -m "Your string here"
> Your String here
> [ 8.5000% 51/600 ]      avg/s:51.0000   etc:2022-06-02 14:36:09

$ (stream) | progpipe -g 600 -v
> [ 2.0000% 12/600 ]      avg/s:12.0000   etc:2022-06-02 14:35:59
> ---
> Days:     .0005
> Hours:    .0136
> Minutes:  .8166
> Seconds:  49
EOFHELP
	exit 0
}

die() {
	printf '%s\n' "${1-}" >&2
	exit 1
}

test_mode() {
	# test_mode function is designed to perform automated tests in a loop.
	# It simulates input for count-up and count-down scenarios.
	# test_mode is useful for verifying that the script works after changes.
	# The function continuously calls itself for ongoing testing.

	echo "progpipe: Starting tests"
	# loop 1, count up
	for i in {11..101}; do
		echo "${i}"
		sleep 0.1
	done |
		$0 -g 101 -d -m "Counting Up"

	# loop 2, count down
	for i in {101..11}; do
		echo "${i}"
		sleep 0.1
	done |
		$0 -g 11 -d -m "Counting Down"

	sleep 3
	test_mode
}

parse_params() {
	goal_number="$1"

	while :; do
		case "${1-}" in
		-h | --help) show_help ;;
		-d | --debug)
			debug_mode=t
			;;
		-v | --verbose)
			verbose_timing_enabled=t
			;;
		-c | --no-clear)
			no_screen_clear=f
			;;
		-m | --message)
			header_message="${2-}"
			shift
			;;
		-g | --goal-num)
			goal_number="${2-}"
			shift
			;;
		-f | --field-sel)
			selected_field="${2-}"
			shift
			;;
		-t | --test-mode)
			test_mode
			shift
			;;
		-?*)
			die "Unknown option: $1"
			;;
		*) break ;;
		esac
		shift
	done

	return 0
}

select_field() {
	# Selects a specified field from tab-separated input for monitoring.
	# Validates and extracts the field as defined by the user (selected_field).
	local a
	local c

	# Validate that the selected field is a positive integer.
	[[ ! $selected_field =~ ^[0-9]+$ ]] &&
		die "ERROR: ${selected_field} is not a number"

	# Hacky string placeholder substitution
	a="awk '{print $ 999}'"
	c=${a/ 999/$selected_field}

	input_value=$(
		echo "$input_value" | eval $c
	)

	[[ -z $input_value ]] &&
		die "ERROR: Field ${selected_field} has no value."

}

ready_run_check() {
	# Checks if initial conditions are met to start processing input.
	# Has the first data update has occurred + enough time elapsed?

	local ready_run

	if [[ -z $first_value ]]; then
		first_value="$input_value"
		ready_run='false'
	fi

	[[ $time_elapsed -le 0 ]] && ready_run='false'

	[[ -z $ready_run ]] && return 0

	echo "Waiting for first data update..."
	return 1
}

update_math() {
	# Performs main calculations for progress estimation.
	# We have to do a lot of float math, and this is a lot "easier"
	# Calculates total work, progress, average rate, and estimated completion.
	local total_work

	# Calculate the total amount of work based on initial and goal values.
	total_work=$(bcmath "$goal_number - $first_value")

	remaining_work=$(bcmath "$goal_number - $input_value")

	progress_elapsed=$(bcmath "$input_value - $first_value")
	average_rate=$(bcmath "$progress_elapsed / $time_elapsed")

	completion_percentage=$(bcmath "$progress_elapsed * 100 / $total_work")

	# check if the progress rate is more than 0/second, or ETC = INF
	if bcmath "$average_rate >= 0" >/dev/null; then
		seconds_remaining=$(bcmath "$remaining_work / $average_rate")
		seconds_remaining=${seconds_remaining%%.*} # clear decimal

		# generate ETC date string in format YYYY-MM-DD HH:MM:SS
		estimated_completion_time=$(date \
			--date="+${seconds_remaining} seconds" \
			'+%Y-%m-%d %T')
	else
		seconds_remaining="INF"
		estimated_completion_time="INF"
	fi
}

bcmath() {
	# Wrapper for bc tool, ensuring consistent precision in calculations.
	# Used for arithmetic operations required in progress tracking.
	echo "$1" |
		sed -r "s/^/scale=4; /" |
		bc -l |
		tr -d "-"
}

draw_prog() {
	# Renders progress output, including percentage, rate, and ETC.
	# Handles screen clearing and displays header message if set.
	local etc_string=''
	etc_string="[ $completion_percentage% $input_value/$goal_number ]"
	etc_string+="	avg/s:$average_rate"
	etc_string+="	etc:$estimated_completion_time"

	# Clear the screen before each redraw
	[[ -z $no_screen_clear ]] && clear

	# Show the header MSG set with -m or --message
	[[ -n $header_message ]] && echo "$header_message"

	# echo "[ $completion_percentage% $progress_elapsed/$goal_number ]	avg/s:$average_rate	etc:$estimated_completion_time" #TODO remove stub
	echo "${etc_string}" # [ 50% 50/100 ] avg/s:1 etc:2022-06-01 12:00:00

	[[ -n $verbose_timing_enabled ]] && print_time_long | column -t
	[[ -n $debug_mode ]] && print_debug | column -t
}

print_time_long() {
	# Provides detailed breakdown of time remaining when verbose mode is enabled
	# Outputs remaining time in days, hours, minutes, and seconds.

	local days
	local hours
	local minutes

	minutes=$(bcmath "$seconds_remaining / 60")
	hours=$(bcmath "$minutes / 60")
	days=$(bcmath "$hours / 24")

	echo "---"
	echo "Days:	$days"
	echo "Hours:	$hours"
	echo "Minutes:	$minutes"
	echo "Seconds:	$seconds_remaining"
}

print_debug() {
	# Outputs internal script variables for debugging purposes.
	# Useful for troubleshooting and understanding script state.

	echo "selected_field:	${selected_field}"
	echo "debug_mode:	${debug_mode}"
	echo "no_screen_clear:	${no_screen_clear}"
	echo "verbose_timing_enabled:	${verbose_timing_enabled}"
	echo "goal_number:	${goal_number}"
	echo "header_message:	${header_message}"
	echo "input_value:	${input_value}"
	echo "first_value:	${first_value}"
	echo "time_elapsed:	${time_elapsed}"
	echo "progress_elapsed:	${progress_elapsed}"
	echo "completion_percentage:	${completion_percentage}"
	echo "average_rate:	${average_rate}"
	echo "remaining_work:	${remaining_work}"
	echo "seconds_remaining:	${seconds_remaining}"
	echo "estimated_completion_time:	${estimated_completion_time}"
}

main() {
	# Main function of the script. Sets up initial variables, parses parameters,
	# and enters the main loop to read and process input.

	local start_time_epoch
	local input_value
	local selected_field
	local no_screen_clear
	local verbose_timing_enabled
	local debug_mode
	local goal_number
	local first_value
	local header_message
	local time_elapsed
	local completion_percentage
	local remaining_work
	local progress_elapsed
	local average_rate
	local seconds_remaining
	local estimated_completion_time

	start_time_epoch=$EPOCHSECONDS

	parse_params "$@"
	[[ -z $goal_number ]] && die "ERROR: Goal is unset. Check -h for usage."

	while read -r input_value <&3; do
		# [[ $input_value == "$goal_number" ]] && exit 0
		time_elapsed=$((EPOCHSECONDS - start_time_epoch))

		# -f or --field-sel awk subscript sel field
		[[ -n $selected_field ]] && select_field

		ready_run_check || continue
		update_math
		draw_prog

	done 3<&0
}

# Execute progpipe by piping data into it: `command | progpipe [options]`
cat | main "$@"
