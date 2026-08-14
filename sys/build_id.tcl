
# Build TimeStamp Verilog Module
# Jeff Wiencrot - 8/1/2011
# Sorgelig - 02/11/2019
proc generateBuildID_Verilog {} {

	# BUILD ID = YYMMDD.NN
	#
	# NN counts the builds made on that date, starting at 01 and resetting each
	# day, because several builds a day is normal and a date alone cannot tell
	# you which one is running on the board.
	#
	# The sequence is always TWO digits so the string is a fixed nine
	# characters. The pause panel packs it into a fixed 32 character line, and
	# a version that changed length would shift the whole line.
	#
	# Unlike the original, this rewrites build_id.v on EVERY compile - that is
	# the point, each compile is a new build and gets its own number.

	set today [clock format [clock seconds] -format %y%m%d]
	set outputFileName "build_id.v"

	set seq 1
	if { [file exists $outputFileName] } {
		set outputFile [open $outputFileName "r"]
		set fileData [read $outputFile]
		close $outputFile

		if { [regexp {BUILD_DATE\s+\"(\d{6})\.(\d+)\"} $fileData -> prevDate prevSeq] } {
			if { $prevDate eq $today } {
				# scan removes any leading zero, which Tcl would otherwise read
				# as octal
				scan $prevSeq %d prevNum
				set seq [expr {$prevNum + 1}]
			}
		} elseif { [regexp {BUILD_DATE\s+\"(\d{6})\"} $fileData -> prevDate] } {
			# an id written before the sequence number existed
			if { $prevDate eq $today } { set seq 2 }
		}
	}

	if { $seq > 99 } { set seq 99 }

	set buildDate "`define BUILD_DATE \"$today.[format %02d $seq]\""

	set outputFile [open $outputFileName "w"]
	puts -nonewline $outputFile $buildDate
	close $outputFile
	post_message "Generated: [pwd]/$outputFileName: $buildDate"
}

# Build CDF file
# Sorgelig - 17/2/2018
proc generateCDF {revision device outpath} {

	set outputFileName "jtag.cdf"
	set outputFile [open $outputFileName "w"]

	puts $outputFile "JedecChain;"
	puts $outputFile "	FileRevision(JESD32A);"
	puts $outputFile "	DefaultMfr(6E);"
	puts $outputFile ""
	puts $outputFile "	P ActionCode(Ign)"
	puts $outputFile "		Device PartName(SOCVHPS) MfrSpec(OpMask(0));"
	puts $outputFile "	P ActionCode(Cfg)"
	puts $outputFile "		Device PartName($device) Path(\"$outpath/\") File(\"$revision.sof\") MfrSpec(OpMask(1));"
	puts $outputFile "ChainEnd;"
	puts $outputFile ""
	puts $outputFile "AlteraBegin;"
	puts $outputFile "	ChainType(JTAG);"
	puts $outputFile "AlteraEnd;"
}

set project_name [lindex $quartus(args) 1]
set revision [lindex $quartus(args) 2]

if {[project_exists $project_name]} {
    if {[string equal "" $revision]} {
        project_open $project_name -revision [get_current_revision $project_name]
    } else {
        project_open $project_name -revision $revision
    }
} else {
    post_message -type error "Project $project_name does not exist"
    exit
}

set device  [get_global_assignment -name DEVICE]
set outpath [get_global_assignment -name PROJECT_OUTPUT_DIRECTORY]

if [is_project_open] {
    project_close
}

generateBuildID_Verilog
generateCDF $revision $device $outpath
