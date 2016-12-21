#!/bin/bash 
 
######### Stacker Version 20161108_1 ##############
# by Chris
 
#set iput folder
STARTFOLDER="raw/microscope/Krios2"
 
# set if include also subdirs (0=no; 1=yes)
REC=0
 
# set number of frames to be expected
END=38
 
# set max disk usage in GB
MAXDU=1000000
 
#set output folder for the stacks (put "." if you want the stacks in the same dir as the frames)
OUTFOLDER="processed/cdienem_yeast_CC_GAT2/micrographs"
 
#set if run in daemon mode (0=no; 1=yes)
DAE=1
 
 
################## dont edit below #################
 
#load relion modules
module purge
module load intel/compiler/64
module load intel/mkl/64
module load intel-mpi/64
module load RELION
 
# this function takes 3 aruments:
# the folder to look into
# if it should be recursive (0/1)
# if it should run as a deamon (0/1)
function stack {
	# get the arguments
	folder=$1
	recursive=$2
	daemon=$3
 
	# create the header for the star file if not existing
	if [ ! -e head.dat ]
		then
		echo "Creating header file..."
		echo $'data_\nloop_\n_rlnImageName' > head.dat
	fi
 
	# create stacker.log; note that it will never override it!
	if [ ! -e stacker.log ]
		then
		echo "Creating log file..."
		echo $'' > stacker.log
	fi	
 
	# decide where the stack will written
	if [ "$OUTFOLDER" == "." ]
	then
		gothere=$folder
	else
		gothere=$OUTFOLDER
	fi
 
	# iterate through all *-00001.mrc files
	echo "Checking $folder for unstacked frames..."
	for file in $folder/*-0001.mrc 
	do
		#check if the stack has been created (read from stacker.log)
		check=`echo ${file}| sed 's|-0001.mrc|.mrcs|'`
		check="${check##*/}"
		# lookup in stacker.log and integrity check
		echo "Check $check"
		para=$(checkOutThatStack $file)
		if [ "$para" = "good" ]
			then
			echo "Processing frames for $(echo ${file}| sed 's|-0001.mrc||')"
			for stack in $(seq -w 01 $END)
			do
				#replaces -0001.mrc with .star, new filename for the temporary star file
				new_file=`echo ${file}| sed 's|-0001.mrc|.star|'`
				new_file="${new_file##*/}"
				#replaces same as above, just for the head
				new_file_head=`echo ${file}| sed 's|-0001.mrc|_head.star|'`
				new_file_head="${new_file_head##*/}"
				# set the output file name by removing the numbers and .mrc and only taking the filename
				out_put=`echo ${file}| sed 's|-0001.mrc||'`
				out_put="${out_put##*/}"
				#picks the current frame from the existing file names by replacing the ending with the frame number from the loop
				tmp=`echo ${file}| sed 's|01.mrc|'$stack'.mrc|'`
				# appends the single frame to the temporary .star file
				echo $tmp >> $gothere/$new_file
			done
			echo "...Done"
			# combines the head and the stacked frames into a new file
			echo "Adding header..."
			cat head.dat $gothere/$new_file > $gothere/$new_file_head
			echo "...Done"
			# uses relion to create a proper mrcs stack from star with head
			echo "Create .mrcs ..."
			relion_stack_create --i $gothere/$new_file_head --o $gothere/$out_put
			# add the created stack to the log
			echo "$check" >> stacker.log
			#removes temporary files (.star and .star with head)
			rm $gothere/$new_file $gothere/$new_file_head -f
 
			# enter a loop and check disk usage of the target directory
			while true; do
				s=$(du $gothere -s)
				usage=${s%%	*} #note that the space between % and * is a tabulator!
				mb=$(((usage/1024)/1024))
				# directly exit the loop if the usage is low enough
				if [ $mb -lt $MAXDU ]
					then
					break
				fi
				echo "Disk usage has reached the limit ($MAXDU GB). Waiting..."
				sleep 5
			done
		else
			echo "$check has been stacked already or is not complete yet."
		fi
	done
	#	if -r flag is set: iterate over sub-directories and start stacker again in subdir
	if [ $recursive -eq 1 ]
		then
		for f in $folder/*; do
  			if [ -d ${f} ]; then
       			stack $f $recursive $daemon
    		fi
		done
	fi
	#   if -d flag is set: start the whole process again with 
	if [ $daemon -eq 1 ]
		then
		echo "Running in daemon mode. Keep looking for unstacked stuff..."
		sleep 5
		stack $STARTFOLDER $recursive $daemon
	fi
}
 
# this function checks if there is enough frame files AND if they are of the same size
function checkOutThatStack {
	local tocheck=`echo ${1}| sed 's|-0001.mrc||'`
	local entry=`echo ${1}| sed 's|-0001.mrc|.mrcs|'`
	entry="${entry##*/}"
	local good=""
	local refsize=$(wc -c < "$1")
	if grep "$entry" stacker.log > /dev/null
	then
		good="bad"
	else
		for fr in $(seq -w 01 $END)
		do
			size=$(wc -c < "$tocheck-00$fr.mrc")
			if [[ ! -e $tocheck-00$fr.mrc || "$size" -ne "$refsize" ]]
			then
				good="bad"
			else
				good="good"
			fi
		done
		echo $good
	fi
}
 
stack $STARTFOLDER $REC $DAE
