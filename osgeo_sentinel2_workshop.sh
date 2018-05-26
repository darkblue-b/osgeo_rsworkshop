#!/bin/bash
###################################################################
# name: osgeo_sentinel2_workshop.sh
# about: Sentinel-2 processing using OSGeo command line tools 
#                 this script should be run from a bash terminal
# notes: make sure to copy Sentinel-2 zip file from the USB drive to your Lubuntu desktop
#                filename is: S2B_MSIL1C_20180421T114349_N0206_R123_T29UNU_20180421T134219.zip
# created on: 21st May 2018
# created by: Daniel McInerney (dmci)
# tested on:  GNU bash, version 4.4.12(1)-release (x86_64-pc-linux-gnu)
# requires:   GDAL/OGR, OTB-bin
###################################################################


## START BY COPYING the directory 'osgeoie' FROM the usb data drive to your Desktop on OSGeo-Live (/home/user/Desktop/) 
## 

# open a bash terminal, the following commands should be run from the terminal

###################################################################
# set up
###################################################################


# change the keyboad to UK qwerty keyboard
setxkbmap -layout gb


# change to directory osgeoie
cd /home/user/Desktop/osgeoie 

# make an output directory within it
mkdir /home/user/Desktop/osgeoie/output

#create a variable to define the working & output directories
export WORKINGDIR=/home/user/Desktop/osgeoie/
export OUTPUTDIR=/home/user/Desktop/osgeoie/output

#check that the variable has been created, 
echo $OUTPUTDIR

# unzip the file
unzip S2B_MSIL1C_20180421T114349_N0206_R123_T29UNU_20180421T134219.zip

# list the contents of the directory, you should have two items:
# 1. the zip file and 
# 2. a .SAFE directory 
ls 

# as space is at a premium on the usb drive, please remove the zip file (provided you have successfully extracted it)
rm *.zip

#rename (shorten) the directory  name
mv S2B_MSIL1C_20180421T114349_N0206_R123_T29UNU_20180421T134219.SAFE S2B_T29UNU_20180421



#change to the SENTINEL2 directory
cd S2B_T29UNU_20180421

# list the contents (ls)
ls

# intro to gdalinfo
gdalinfo --help


gdalinfo --version

#list supported formats 
gdalinfo --formats


##check for sentinel2
gdalinfo --formats | grep 'SENTINEL'


#get information about the SENTINEL-2 data (pay attention to sub-datasets listed)
gdalinfo MTD_MSIL1C.xml

## how many SENTINEL-2 sub-datasets can you see?

# now re-run the command, but add the subdataset (-sd) option 
gdalinfo -sd 1 MTD_MSIL1C.xml


for i in 1 2 3 4; do echo $i; gdalinfo -sd $i MTD_MSIL1C.xml | grep wavelength; done

###################################################################
# data preprocessing
###################################################################


## gdal_translate
gdal_translate --help 

# gdal_translate to extract and clip the image
## options are "-of"  "-projwin" "-co"
gdal_translate -of GTiff -projwin 583049 5891167 607528 5869311 -co COMPRESS=LZW SENTINEL2_L1C:MTD_MSIL1C.xml:10m:EPSG_32629 S2B_subset_32629.tif


#check the output using gdalinfo
gdalinfo S2B_subset_32629.tif

#reproject the image from UTM (32629) to ITM (2157)
gdalwarp -s_srs 'epsg:32629' -t_srs 'epsg:2157' S2B_subset_32629.tif S2B_subset_2157.tif


#gdal_calc.py
gdal_calc.py --help

#let's create an NDVI image using gdal_calc.py
gdal_calc.py -A S2B_subset_2157.tif --A_band=1 -B S2B_subset_2157.tif --B_band=4 --calc="((B.astype(float)-A)/(B.astype(float)+A))*100" --outfile=S2B_subset_ndvi.tif

#gdal_merge.py
gdal_merge.py --help

# create a stack of the images
gdal_merge.py -o S2B_subset_bands_ndvi_2157.tif S2B_subset_2157.tif S2B_subset_ndvi.tif -separate 

#check the output with gdalinfo
gdalinfo S2B_subset_ndvi.tif 


###################################################################
# image classification
###################################################################

# run an unsupervised classification
otbcli_KMeansClassification -h

# run an unsupervised classification with 6 classes
otbcli_KMeansClassification -in S2B_subset_bands_ndvi_2157.tif -out $OUTPUTDIR/S2B_subset_unsupervised.tif -nc 15

# let's reclass this output to e.g. forest (1) and non-forest areas (2)
gdal_calc.py -A   $OUTPUTDIR/S2B_subset_unsupervised.tif --A_band=1 --calc="(logical_and(A==1, A==5, A==10)*1) + ((A>1)*(A<5)*2) + ((A>5)*(A<10)*2) + ((A>10)*2)" --outfile=$OUTPUTDIR/S2B_subset_unsupervised_rc.tif

##check the output in QGIS

###################################################################

# supervised classification (random forest classification using Orfeo Toolbox)

##make sure you are in the correct directory
cd /home/user/Desktop/osgeoie/S2B_T29UNU_20180421/


# Compute Image Statistics (required step for OTB classification)
otbcli_ComputeImagesStatistics -il S2B_subset_bands_ndvi_2157.tif -bv 0 -out S2B_subset_2157_stats.xml


# Train Image Classifier - Random Forest classifier 
otbcli_TrainImagesClassifier -io.il S2B_subset_bands_ndvi_2157.tif -io.vd $WORKINGDIR/training.shp -io.imstat S2B_subset_2157_stats.xml -sample.mt -1 -sample.bm 0 -sample.vtr 0.0 -sample.vfn Class -classifier rf -classifier.rf.nbtrees 500 -classifier.rf.min 12 -classifier.rf.acc True -io.out output_model.txt -io.confmatout confmatrix2.csv


# image classification
otbcli_ImageClassifier -in S2B_subset_bands_ndvi_2157.tif -imstat S2B_subset_2157_stats.xml -model output_model.txt -out $OUTPUTDIR/S2B_subset_supervised.tif

# generate Confusion Matrix using OTB for Accuracy Assessment
otbcli_ComputeConfusionMatrix -in $OUTPUTDIR/S2B_subset_supervised.tif -out $OUTPUTDIR/confusion_matrix.csv -ref vector -ref.vector.in $WORKINGDIR/validation.shp -ref.vector.field Class -ref.vector.nodata -9999 






