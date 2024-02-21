Macro "astroglia_filter" {

function to_stack(image_name) { 
	// Transform image into Z stack with max intensity projection of channel 2
	rename(image_name);
	run("Split Channels");
	close("C1-"+image_name);
	selectImage("C2-"+image_name);
	run("Z Project...", "projection=[Max Intensity]");
	close("C2-"+image_name);
	selectImage("MAX_C2-"+image_name);
	rename(image_name);
	}


function image_preprocessing() {
// This function sets pixel scale, subtracts background, and applies a smooth median filter
		run("Set Scale...", "distance=1 known=1 unit=p global");
		run("8-bit");
		image_median = getValue("Median");
		if (image_median > 125) {
			run("Invert");
		}
		run("Pseudo flat field correction", "blurring=100 hide");
		run("Subtract Background...", "rolling=&background_substraction sliding");		
		// Reduce contrast differences within cells and homogenize background
		run("Median...", "radius=1");
}

function segmentation() { 
// This function duplicates the original image and applies the "unsharp" filter to enhance cells and obtain a mask.
// It then duplicates the mask and skeletonizes it. Subsequently, it filters the low frequencies of the original image to separate
// nearby cells (filtering small energy variations present between two cells that could generate unions when applying thresholds)
// then multiplies the "unsharp" mask with the "bandpass" to obtain a mask containing only the cell area
// ("bandpass" has a lot of background that is remedied by multiplying by the background of "unsharp").
// Finally, it adds the mask obtained in the previous step with the skeletonized mask to join those cell fragments
// that could have been separated by the application of the band filter.     

		// unsharp: will be used to generate the complete cell skeleton
		run("Duplicate...", "title=unsharp");
		run("Unsharp Mask...", "radius=5 mask=&unsharp_degree");
		setAutoThreshold("Li dark");
		setOption("BlackBackground", true);
		run("Convert to Mask");
		
		// esk: will be used for the complete skeleton of the image
		// unsharp: will be used as a base in the image multiplication
		run("Duplicate...", "title=esk");
		run("Skeletonize");
		
		// apply bandpass filter to remove low frequencies and thus increase segmentation between cells
		// then a high threshold is applied to cover most of the cells
		selectWindow(image_name);
		run("Bandpass Filter...", "filter_large=5 filter_small=1 suppress=None tolerance=0 autoscale saturate");
		setAutoThreshold("Percentile dark");
		run("Convert to Mask");
		rename("bandpass");

		// multiply the "bandpass" image and the "unsharp" image to select only
		// the area containing the cells
		imageCalculator("Multiply create", "bandpass","unsharp");

		// add the image of the previous step ("result of bandpass") with the image "esk" to keep together those
		// segments that may have been separated
		imageCalculator("Add create", "Result of bandpass","esk");
		rename("mask");
		close("\\Others");
}

function particles_selection() { 
// This function selects particles larger than 3000 pixels (which should include the cells being analyzed).
// Subsequently, it inverts the image and selects those particles smaller than 100 pixels, which would correspond to gaps
// within the cells. Finally, it adds the cell mask with the intercellular gap mask.
	
	// select particles larger than 3000 pixels and smaller than 60000 pixels
	run("Analyze Particles...", "size=&particles_size-&large_size pixel show=Masks");
	run("Invert LUT");
	rename("im");
	run("Duplicate...", "title=h");
	
	// Process the image to remove internal gaps in the cells 		
	run("Invert");
	
	// select particles smaller than 100 pixels, corresponding to gaps within the cells
	run("Analyze Particles...", "size=0-&small_size pixel show=Masks");
	run("Invert LUT");

	imageCalculator("Add create", "Mask of h", "im");
	rename("binary_"+file);
	
	// perform 50 cycles of outlier removal to eliminate gaps in the center of the cells
	for (i = 0; i < 50; i++) {
	run("Remove Outliers...", "radius=1 threshold=50 which=Dark");
	}
	close("\\Others");
	if (process == "Process") {
		saveAs("Tiff", binary_folder+"binary_"+file);
	}
}


// Set the approximate size of the particle to be analyzed
Dialog.create("Segmentation and analysis settings");
Dialog.addMessage("Segmentation settings:", 15);
var min = 0;
var max = 300;
var default = 75;
Dialog.addSlider("Background subtraction", min, max, default);

var min = 0;
var max = 0.9;
var default = 0.8;
Dialog.addSlider("Unsharp mask degree", min, max, default);

var min = 0;
var max = 50000;
var default = 2000;
Dialog.addSlider("Lower particle size", min, max, default);
Dialog.addRadioButtonGroup("", newArray("Test", "Process"), 1, 3, "Process");
Dialog.show();

background_substraction = Dialog.getNumber();
unsharp_degree = Dialog.getNumber();
particles_size = Dialog.getNumber();
small_size = particles_size/30;
large_size = particles_size*15;
process = Dialog.getRadioButton();

if (process == "Test") {
	path_test = File.openDialog("Choose an image");
	open(path_test);
	file = File.getName(path_test);
	image_preprocessing();
	segmentation();
	particles_selection();
}
else {
// Create folders to save results and processed images, set parameters to measure, and 
// delete possible open results and images before macro execution
run("Clear Results");
run("Close All");
close(".csv*");
close("Summary");
close("Roi Manager");
folder = getDirectory("Directory");
list = getFileList(folder);
run("Set Measurements...", "area perimeter shape feret's integrated limit redirect=None decimal=3");
results_folder = folder+"results"+File.separator;
binary_folder = results_folder+"binaryImages"+File.separator;

// create directories
File.makeDirectory(results_folder); 
File.makeDirectory(binary_folder);

for (image_number = 0; image_number < list.length; image_number++)
	{
	file = File.getName(list[image_number]);
	if (endsWith(file, "oib"))
		{
		im = folder+file;
		run("Bio-Formats Windowless Importer", "open="+"[im]");
		open(folder+file);
		image_name = split(file, ".");
		image_name = image_name[0];
		to_stack(image_name);
		// Image preprocessing to obtain a binary image and a skeletonized one
		image_preprocessing();
		segmentation();
		particles_selection();
		
		}
		}
	}
close("*");
}