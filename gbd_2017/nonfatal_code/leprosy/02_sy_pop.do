// **********************************************************************
// Purpose:        This step template should be submitted from the 00_master.do file either by submitting all steps or selecting one or more steps to run in "steps" global
// Description:   Pulls in single age population estimates by country, and interpolates incidence estimates

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

// LOAD SETTINGS FROM STEP CODE (NO NEED TO EDIT THIS SECTION)

	// prep stata
	clear all
	set more off
	set maxvar 32000
	if c(os) == "Unix" {
		global prefix "FILEPATH"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global prefix "FILEPATH"
	}

// define locals from qsub command
	local date 			`1'
	local step_num 		`2'
	local step_name		`3'
	local location 		`4'
	local code_dir 		`5'
	local in_dir 		`6'
	local out_dir 		`7'
	local tmp_dir 		`8'
	local root_tmp_dir 	`9'
	local root_j_dir 	`10'

	// write log if running in parallel and log is not already open
	cap log using "FILEPATH/`step_num'_`location'.smcl", replace
	if !_rc local close 1
	else local close 0

	// directory for standard code file
	adopath + FILEPATH
	adopath + FILEPATH

	// get demographics
    get_location_metadata, location_set_id(9) clear
    keep if most_detailed == 1 & is_estimate == 1
    keep location_id region_name
    tempfile location_data
    save `location_data', replace

    // get demographics
   	/*get_demographics, gbd_team(ADDRESS) clear
	local years = "$year_ids"
	local sexes = "$sex_ids" */
	numlist "1970/2017"
	local years "`r(numlist)'"
	local sexes 1 2

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

** First, prepare population files by age and year so we can use ODE

** get the single years first
	numlist "49/142"
	local sy_ages `r(numlist)'
	get_population, age_group_id(`sy_ages') location_id(`location') sex_id(1 2) year_id(`years') clear single_year_age(TRUE)
		tempfile sy_populations
		save `sy_populations'

** pull in non-single-year populations for neonates and 95+
	get_population, year_id(`years') location_id(`location') sex_id(1 2) age_group_id(2 3 4 235) single_year_age(FALSE) clear
		append using "`sy_populations'"

		tempfile temp_pops
		save `temp_pops'

* pull age group ids so that they are in age form
	get_ids, table(age_group) clear
		merge 1:m age_group_id using `temp_pops', keep(3) nogen

* change ages so that they are numeric
	replace age_group_name = "95" if age_group_name == "95 plus"

	tempfile grp_pops
	save `grp_pops'

	replace age_group_name = "0" if age_group_name == "Early Neonatal" | age_group_name == "Late Neonatal" | age_group_name == "Post Neonatal"

	drop age_group_id
	rename age_group_name age

	fastcollapse population, type(sum) by(location_id year_id age sex_id)
	tempfile temp_pops
	save `temp_pops', replace

	use "`tmp_dir'/loc_iso3.dta", clear
	keep if location_id == `location'
	merge 1:m location_id using `temp_pops', keep(3) nogen

	drop location_id
	rename year_id year
	rename population pop

	gen sex = "male" if sex_id == 1
	replace sex = "female" if sex_id == 2
	drop sex_id
	export delimited "FILEPATH/sy_pop_`location'.csv", replace

** interpolate age-pattern in incidence for years 1990 - 2016
	interpolate, gbd_id_type(modelable_entity_id) gbd_id(10722) measure_id(6) location_id(`location') reporting_year_start(1980) reporting_year_end(2017) source("ADDRESS") clear
	export delimited "FILEPATH/`location'.csv", replace

** write check here
	file open finished using "FILEPATH/finished_loc`location'.txt", replace write
	file close finished

** close logs
	if `close' log close
	clear
