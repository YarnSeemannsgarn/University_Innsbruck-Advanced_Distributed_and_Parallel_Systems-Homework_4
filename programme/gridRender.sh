#!/bin/bash

declare -a GRID_RESOURCES=("karwendel.dps.uibk.ac.at" "login.leo1.uibk.ac.at/jobmanager-sge")
GM_GRID_RESOURCE="${GRID_RESOURCES[0]}"
BIN_DIR=./bin
INPUT_DIR=./inputdata
RESULT_DIR=./results
LOG_DIR=./log
REMOTE_DIR=./tmp/homework_4
REMOTE_BIN_DIR=$REMOTE_DIR/$BIN_DIR
REMOTE_INPUT_DIR=$REMOTE_DIR/$INPUT_DIR
REMOTE_RESULT_DIR=$REMOTE_DIR/$RESULT_DIR

mkdir -p $LOG_DIR/

echo "Create proxy"
grid-proxy-init

for grid_resource in ${GRID_RESOURCES[@]};
do
    echo "Copy files to grid resource: $grid_resource and set permissions"
    globus-url-copy -r -create-dest -rp $BIN_DIR/ "gsiftp://${grid_resource%/*}/$REMOTE_BIN_DIR/"
    globus-url-copy -r -create-dest -rp $INPUT_DIR/ "gsiftp://${grid_resource%/*}/$REMOTE_INPUT_DIR/"
    globus-job-run "$grid_resource" /bin/sh -c "rm -fr $REMOTE_RESULT_DIR; mkdir $REMOTE_RESULT_DIR; /bin/chmod +x $REMOTE_BIN_DIR/povray $REMOTE_BIN_DIR/gm" &
done
wait

# Read .ini file to get frame numbers (Copied from homework 2)
while read line
do
    if [[ $line == Initial_Frame* ]] || [[ $line == Final_Frame* ]] ;
    then
	equal_pos=`expr index $line =`
	length=`expr length $line`
	frame_number=${line:equal_pos:length}
	
	if [[ $line == Initial_Frame* ]] ;
	then
	    INITIAL_FRAME=$frame_number
	else
	    FINAL_FRAME=$frame_number
	fi
    fi
done < ${INPUT_DIR}/scherk.ini

# M = number of frames
M=$((FINAL_FRAME - INITIAL_FRAME + 1))
echo "$M frames will be rendered on the grid"

# N = number of grid resources
N=${#GRID_RESOURCES[@]}

subset_start_frame=1
subsets_per_processor=$(( M/N ))
modulo=`expr $M % $N`
i=0
for grid_resource in ${GRID_RESOURCES[@]};
do
    i=$((i+1))
    subset_end_frame=$((subset_start_frame + subsets_per_processor - 1))
    if [[ $i -le $modulo ]]
    then
	subset_end_frame=$((subset_end_frame + 1))
    fi
    frames=$((subset_end_frame - subset_start_frame + 1))

    echo "Render frame ${subset_start_frame}-${subset_end_frame} on $grid_resource"
    {
	START=$(date +%s.%N)
	globus-job-run "$grid_resource" /bin/sh -c "cd $REMOTE_RESULT_DIR; ../$BIN_DIR/povray ../$INPUT_DIR/scherk.ini +I../$INPUT_DIR/scherk.pov +Orender.png +FN +W1024 +H768 +SF$subset_start_frame +EF$subset_end_frame"
	END=$(date +%s.%N)
	TIME=$(echo "$END - $START" | bc | awk '{printf "%f", $0}')
	echo "Execution time (without copying files) for $frames frames on grid resource $grid_resource: $TIME seconds"

	if [ $grid_resource != $GM_GRID_RESOURCE ]; 
	then
	    echo "Copy result files from $grid_resource to $GM_GRID_RESOURCE for creating the gif"
	    globus-url-copy -r -rp "gsiftp://${grid_resource%/*}/$REMOTE_RESULT_DIR/" "gsiftp://${GM_GRID_RESOURCE%/*}/$REMOTE_RESULT_DIR/"
	fi
    } 2> $LOG_DIR/${grid_resource%/*}.err &

    subset_start_frame=$((subset_end_frame + 1))
done
wait

echo "Merge rendered images to one gif on $GM_GRID_RESOURCE"
globus-job-run "$GM_GRID_RESOURCE" "$REMOTE_BIN_DIR/gm" convert -loop 0 -delay 0 "$REMOTE_RESULT_DIR/render*.png" "$REMOTE_RESULT_DIR/render.gif"

echo "Copy gif to localhost"
globus-url-copy -rp "gsiftp://${GM_GRID_RESOURCE%/*}/$REMOTE_RESULT_DIR/render.gif" ./render.gif

echo "Close proxy"
grid-proxy-destroy

echo "For sheduling results read the report"
