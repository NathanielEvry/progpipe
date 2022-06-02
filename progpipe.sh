#!/bin/bash

###############################################################################
# Writen by Nathaniel Evry nathaniel@quub.space
# progpipe: useful for people who need to wait. Often.
# https://github.com/altometer/progpipe
###############################################################################

show_help() {
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
	# Calls on self with debug options and a 10sec runtime

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
			flag_debug=t
			;;
		-v | --verbose)
			flag_verbose_time_remaining=t
			;;
		-c | --no-clear)
			flag_no_lineclear=f
			;;
		-m | --message)
			string_header_msg="${2-}"
			shift
			;;
		-g | --goal-num)
			goal_number="${2-}"
			shift
			;;
		-f | --field-sel)
			flag_select_field="${2-}"
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
	local a
	local c

	[[ ! $flag_select_field =~ ^[0-9]+$ ]] &&
		die "ERROR: ${flag_select_field} is not a number"

	# a="awk -F'\t' '{print $ 999}'"
	a="awk '{print $ 999}'"
	c=${a/ 999/$flag_select_field}

	stdin_holder=$(
		echo "$stdin_holder" | eval $c
	)

	[[ -z $stdin_holder ]] &&
		die "ERROR: Field ${flag_select_field} has no value."

}

ready_run_check() {
	local ready_run

	if [[ -z $first_value ]]; then
		first_value="$stdin_holder"
		ready_run='false'
	fi

	[[ $elapsed_time -le 0 ]] && ready_run='false'

	[[ -z $ready_run ]] && return 0

	echo "Waiting for first data update..."
	return 1
}

update_math() {
	# [[ $goal_number == 0 ]] && goal_number=$first_value
	# If goal number < current number
	local total_work

	total_work=$(bcmath "$goal_number - $first_value")

	work_remaining=$(bcmath "$goal_number - $stdin_holder")

	elapsed_progress=$(bcmath "$stdin_holder - $first_value")
	avg_rate=$(bcmath "$elapsed_progress / $elapsed_time")

	percent_complete=$(bcmath "$elapsed_progress * 100 / $total_work")

	# check if the rate > 0, or ETC = INF
	if bcmath "$avg_rate >= 0" >/dev/null; then
		seconds_left=$(bcmath "$work_remaining / $avg_rate")
		seconds_left=${seconds_left%%.*} # clear decimal

		# generate ETC date string in format YYYY-MM-DD HH:MM:SS
		epoch_etc=$(date \
			--date="+${seconds_left} seconds" \
			'+%Y-%m-%d %T')
	else
		seconds_left="INF"
		epoch_etc="INF"
	fi
}

bcmath() {
	echo "$1" |
		sed -r "s/^/scale=4; /" |
		bc -l |
		tr -d "-"
}

draw_prog() {
	local etc_string=''
	etc_string="[ $percent_complete% $stdin_holder/$goal_number ]"
	etc_string+="	avg/s:$avg_rate"
	etc_string+="	etc:$epoch_etc"

	# Clear the screen before each redraw
	[[ -z $flag_no_lineclear ]] && clear

	# Show the header MSG set with -m or --message
	[[ -n $string_header_msg ]] && echo "$string_header_msg"

	# echo "[ $percent_complete% $elapsed_progress/$goal_number ]	avg/s:$avg_rate	etc:$epoch_etc" #TODO remove stub
	echo "${etc_string}" # [ 50% 50/100 ] avg/s:1 etc:2022-06-01 12:00:00

	[[ -n $flag_verbose_time_remaining ]] && print_time_long | column -t
	[[ -n $flag_debug ]] && print_debug | column -t
}

print_time_long() {
	local days
	local hours
	local minutes

	minutes=$(bcmath "$seconds_left / 60")
	hours=$(bcmath "$minutes / 60")
	days=$(bcmath "$hours / 24")

	echo "---"
	echo "Days:	$days"
	echo "Hours:	$hours"
	echo "Minutes:	$minutes"
	echo "Seconds:	$seconds_left"
}

print_debug() {
	echo "flag_select_field:	${flag_select_field}"
	echo "flag_debug:	${flag_debug}"
	echo "flag_no_lineclear:	${flag_no_lineclear}"
	echo "flag_verbose_time_remaining:	${flag_verbose_time_remaining}"
	echo "goal_number:	${goal_number}"
	echo "string_header_msg:	${string_header_msg}"
	echo "stdin_holder:	${stdin_holder}"
	echo "first_value:	${first_value}"
	echo "elapsed_time:	${elapsed_time}"
	echo "elapsed_progress:	${elapsed_progress}"
	echo "percent_complete:	${percent_complete}"
	echo "avg_rate:	${avg_rate}"
	echo "work_remaining:	${work_remaining}"
	echo "seconds_left:	${seconds_left}"
	echo "epoch_etc:	${epoch_etc}"
}

main() {
	local epoch_start
	local stdin_holder
	local flag_select_field
	local flag_no_lineclear
	local flag_verbose_time_remaining
	local flag_debug
	local goal_number
	local first_value
	local string_header_msg
	local elapsed_time
	local percent_complete
	local work_remaining
	local elapsed_progress
	local avg_rate
	local seconds_left
	local epoch_etc

	epoch_start=$EPOCHSECONDS

	parse_params "$@"
	[[ -z $goal_number ]] && die "ERROR: Goal is unset"

	while read -r stdin_holder <&3; do
		# [[ $stdin_holder == "$goal_number" ]] && exit 0
		elapsed_time=$((EPOCHSECONDS - epoch_start))

		# -f or --field-sel awk subscript sel field
		[[ -n $flag_select_field ]] && select_field

		ready_run_check || continue
		update_math
		draw_prog

	done 3<&0
}

cat | main "$@"
