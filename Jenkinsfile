pipeline {
    agent any
    // In additional to manual runs, trigger somewhere at midnight to
    // give us the max time in a day to get things right.
    triggers {
	// Master never runs--Feb 31st.
	//cron('0 0 31 2 *')
	// Nightly @12am, for "snapshot", skip "release" night.
	//cron('0 0 2-31/2 * *')
	// First of the month @12am, for "release" (also "current").
	//cron('0 0 1 * *')
	// MWF @9pm (crontab on prod should have run at 8pm, in about 10m)
	cron('0 21 * * 1,3,5')
    }
    environment {

	///
	/// Internal run variables.
	///

	// The branch of geneontology/go-site to use.
	TARGET_GO_SITE_BRANCH = 'master'
	// The branch of geneontology/go-stats to use.
	TARGET_GO_STATS_BRANCH = 'master'
	// The branch of go-ontology to use.
	TARGET_GO_ONTOLOGY_BRANCH = 'master'
	// The branch of minerva to use.
	TARGET_MINERVA_BRANCH = 'master'
	// The branch of ROBOT to use in one silly section.
	// Necessary due to java version jump.
	// https://github.com/ontodev/robot/issues/997
	TARGET_ROBOT_BRANCH = 'master'
	// The branch of noctua-models to use.
	TARGET_NOCTUA_MODELS_BRANCH = 'master'
	// The people to call when things go bad. It is a comma-space
	// "separated" string.
	// TARGET_ADMIN_EMAILS = 'sjcarbon@lbl.gov,debert@usc.edu,smoxon@lbl.gov'
	// TARGET_SUCCESS_EMAILS = 'sjcarbon@lbl.gov,debert@usc.edu,suzia@stanford.edu,smoxon@lbl.gov'
	// TARGET_RELEASE_HOLD_EMAILS = 'sjcarbon@lbl.gov,debert@usc.edu,pascale.gaudet@sib.swiss,pgaudet1@gmail.com,smoxon@lbl.gov'
	TARGET_ADMIN_EMAILS = 'sjcarbon@lbl.gov'
	TARGET_SUCCESS_EMAILS = 'sjcarbon@lbl.gov'
	TARGET_RELEASE_HOLD_EMAILS = 'sjcarbon@lbl.gov'
	// The file bucket(/folder) combination to use.
	//TARGET_BUCKET = 'go-data-product-snapshot'
	TARGET_BUCKET = 'go-data-TBD'
	// The URL prefix to use when creating site indices.
	//TARGET_INDEXER_PREFIX = 'http://snapshot.geneontology.org'
	TARGET_INDEXER_PREFIX = 'null'
	// This variable should typically be 'TRUE', which will cause
	// some additional basic checks to be made. There are some
	// very exotic cases where these check may need to be skipped
	// for a run, in that case this variable is set to 'FALSE'.
	WE_ARE_BEING_SAFE_P = 'TRUE'
	// Sanity check for solr index being built--overall min count.
	// See https://github.com/geneontology/pipeline/issues/315 .
	// Only used on release attempts (as it saves QC time and
	// getting the number for all branches would be a trick).
	SANITY_SOLR_DOC_COUNT_MIN = 11000000
	SANITY_SOLR_BIOENTITY_DOC_COUNT_MIN = 1400000
	// Control make to get through our loads faster if
	// possible. Assuming we're cpu bound for some of these...
	// wok has 48 "processors" over 12 "cores", so I have no idea;
	// let's go with conservative and see if we get an
	// improvement.
	MAKECMD = 'make --jobs --max-load 12.0'
	//MAKECMD = 'make'

	///
	/// PANTHER/PAINT metadata.
	///

	PANTHER_VERSION = '19.0'

	///
	/// Application tokens.
	///

	// The Zenodo concept ID to use for releases (and occasionally
	// master testing).
	//ZENODO_ARCHIVE_CONCEPT = '425666'
	ZENODO_ARCHIVE_CONCEPT = 'null'
	// Distribution ID for the AWS CloudFront for this branch,
	// used soley for invalidations. Versioned release does not
	// need this as it is always a new location and the index
	// upload already has an invalidation on it. For current,
	// snapshot, and experimental.
	//AWS_CLOUDFRONT_DISTRIBUTION_ID = 'E3UPPWY0HYLLL2'
	//AWS_CLOUDFRONT_RELEASE_DISTRIBUTION_ID = 'E2HF1DWYYDLTQP'
	AWS_CLOUDFRONT_DISTRIBUTION_ID = 'null'
	AWS_CLOUDFRONT_RELEASE_DISTRIBUTION_ID = 'null'

	///
	/// Ontobio Validation
	///
	// WARNING: This will need to be changed.
	VALIDATION_ONTOLOGY_URL="http://snapshot.geneontology.org/ontology/go.json"

	///
	/// Minerva input.
	///

	// Minerva operating profile.
	// WARNING: This will need to be changed.
	MINERVA_INPUT_ONTOLOGIES = [
	    "http://snapshot.geneontology.org/ontology/extensions/go-lego.owl"
	].join(" ")

	///
	/// GOlr/AmiGO input.
	///

	// GOlr load profile.
	GOLR_SOLR_MEMORY = "256G"
	GOLR_LOADER_MEMORY = "256G"
	GOLR_INPUT_ONTOLOGIES = [
	    "http://snapshot.geneontology.org/ontology/extensions/go-amigo.owl"
	].join(" ")
	// WARNING: hard-coded for the moment.
	GOLR_INPUT_GAFS = [
	    "http://skyhook.berkeleybop.org/confinement-for-pipeline-388/union.gaf.gz"
	].join(" ")
	GOLR_INPUT_PANTHER_TREES = [
	    "http://snapshot.geneontology.org/products/panther/arbre.tgz"
	].join(" ")

	///
	/// Groups to run and tests to avoid running during the current
	/// mega-make.
	///

	// The gorule tag is used to identify which rules to suppress
	// reports from during the megastep and during templating the
	// reports after the megastep. The tags are currently
	// respected at two times in the pipeline: the gorules report
	// take the flag as a CLI argument, supressing it; ontobio
	// takes it during the same stage as the JSON
	// generation/parsing step, to supress the .md output. At this
	// time, this variable can be either nothing or empty string
	// for no rule suppression (default behavior everything), or a
	// single value (practically speaking pretty much always
	// "silent")
	GORULE_TAGS_TO_SUPPRESS="silent"

	// Optional. Groups to run.
	//RESOURCE_GROUPS=""
	// Optional. Datasets to skip within the resources that we
	// will run (defined in the line above).
	//DATASET_EXCLUDES=""
	// Optional. This acts as an override, /if/ it's grabbed (as
	// defined above).
	//GOA_UNIPROT_ALL_URL=""

    }
    options{
	timestamps()
	buildDiscarder(logRotator(numToKeepStr: '14'))
    }
    stages {
	// Very first: pause for a few minutes to give a chance to
	// cancel and clean the workspace before use.
	stage('Ready and clean') {
	    steps {

		// Check to make sure we have coherent metadata so we
		// don't clobber good products.
		watchdog();

		// Give us a minute to cancel if we want.
//		sleep time: 1, unit: 'MINUTES'
		cleanWs deleteDirs: true, disableDeferredWipeout: true
	    }
	}

	stage('Initialize') {
	    steps {

		///
		/// Automatic run variables.
		///

		// Pin dates and day to beginning of run.
		script {
		    env.START_DATE = sh (
			script: 'date +%Y-%m-%d',
			returnStdout: true
		    ).trim()

		    env.START_DAY = sh (
			script: 'date +%A',
			returnStdout: true
		    ).trim()
		}

		// Reset base.
		initialize();

		sh 'env > env.txt'
		sh 'echo $BRANCH_NAME > branch.txt'
		sh 'echo "$BRANCH_NAME"'
		sh 'echo "$JOB_NAME"'
		sh 'cat env.txt'
		sh 'cat branch.txt'
		sh 'echo $START_DAY > dow.txt'
		sh 'echo "$START_DAY"'
		sh 'echo $START_DATE > date.txt'
		sh 'echo "$START_DATE"'
	    }
	}
	stage('Ready production software') {
	    steps {

		dir('./minerva') {
		    // Remember that git lays out into CWD.
		    git branch: TARGET_MINERVA_BRANCH, url: 'https://github.com/geneontology/minerva.git'
		    sh './build-cli.sh'
		    // Attempt to rsync produced into bin/.
		    withCredentials([file(credentialsId: 'skyhook-private-key', variable: 'SKYHOOK_IDENTITY'), string(credentialsId: 'skyhook-machine-private', variable: 'SKYHOOK_MACHINE')]) {
			sh 'rsync -avz -e "ssh -o StrictHostKeyChecking=no -o IdentitiesOnly=true -o IdentityFile=$SKYHOOK_IDENTITY" minerva-cli/bin/minerva-cli.* skyhook@$SKYHOOK_MACHINE:/home/skyhook/pipeline-raw-go-cam/$BRANCH_NAME/bin/'
		    }
		}
	    }
	}
	stage('Minerva generations') {
	    steps {

		// May be parallelized in the future, but may need to
		// serve as input into into mega step.
		script {

		    // Create a relative working directory and setup our
		    // data environment.
		    dir('./json-noctua-models') {

			// Pull saved models into our environment from
			// S3, rather than GH.
			withCredentials([string(credentialsId: 'aws_go_access_key', variable: 'AWS_ACCESS_KEY_ID'), string(credentialsId: 'aws_go_secret_key', variable: 'AWS_SECRET_ACCESS_KEY')]) {
			    sh 'aws s3 cp s3://go-data-product-live-go-cam/ttl ./models/ --recursive --exclude "*" --include "*.ttl"'
			}

			// Make all software products
			// available in bin/ (and lib/).
			sh 'mkdir -p bin/'
			withCredentials([file(credentialsId: 'skyhook-private-key', variable: 'SKYHOOK_IDENTITY'), string(credentialsId: 'skyhook-machine-private', variable: 'SKYHOOK_MACHINE')]) {
			    sh 'rsync -avz -e "ssh -o StrictHostKeyChecking=no -o IdentitiesOnly=true -o IdentityFile=$SKYHOOK_IDENTITY" skyhook@$SKYHOOK_MACHINE:/home/skyhook/pipeline-raw-go-cam/$BRANCH_NAME/bin/* ./bin/'
			}
			sh 'chmod +x bin/*'

			// Compile models.
			sh 'mkdir -p jsonout'
			withEnv(['MINERVA_CLI_MEMORY=128G']){
			    // "Import" models.
			    sh './bin/minerva-cli.sh --import-owl-models -f models -j blazegraph.jnl'
			    // JSON out to directory.
			    sh './bin/minerva-cli.sh --dump-owl-json --journal blazegraph.jnl --ontojournal blazegraph-go-lego-reacto-neo.jnl --folder jsonout'
			}

			// Get into S3, cohabitating safely with TTL.
			withCredentials([string(credentialsId: 'aws_go_access_key', variable: 'AWS_ACCESS_KEY_ID'), string(credentialsId: 'aws_go_secret_key', variable: 'AWS_SECRET_ACCESS_KEY')]) {
			    sh 'aws s3 cp ./jsonout/ s3://go-data-product-live-go-cam/product/json/low-level/ --recursive --exclude "*" --include "*.json"'
			}

			// // Compress and out.
			// //sh 'tar --use-compress-program=pigz -cvf noctua-models-json.tgz -C jsonout .'
			// withCredentials([file(credentialsId: 'skyhook-private-key', variable: 'SKYHOOK_IDENTITY'), string(credentialsId: 'skyhook-machine-private', variable: 'SKYHOOK_MACHINE')]) {
			//     sh 'scp -r -o StrictHostKeyChecking=no -o IdentitiesOnly=true -o IdentityFile=$SKYHOOK_IDENTITY jsonout skyhook@$SKYHOOK_MACHINE:/home/skyhook/pipeline-raw-go-cam/$BRANCH_NAME/products/json/'
			// }

			// Product the metadata.
			dir('./jsonout') {
			    sh 'wget -N https://raw.githubusercontent.com/geneontology/go-site/$TARGET_GO_SITE_BRANCH/scripts/gen-model-meta.py'
			    sh 'python3 gen-model-meta.py > ../metadata.json'
			}
			// Get into S3, cohabitating safely with TTL.
			withCredentials([string(credentialsId: 'aws_go_access_key', variable: 'AWS_ACCESS_KEY_ID'), string(credentialsId: 'aws_go_secret_key', variable: 'AWS_SECRET_ACCESS_KEY')]) {
			    sh 'aws s3 cp ./metadata.json s3://go-data-product-live-go-cam/product/json/provider-to-model.json'
			}
		    }
		}
	    }
	}
    }
    post {
	// Let's let our people know if things go well.
	success {
	    script {
		if( env.BRANCH_NAME == 'release' || env.BRANCH_NAME == 'snapshot-post-fail' || env.BRANCH_NAME == 'derivatives-from-goa' || env.BRANCH_NAME == 'main' ){
		    echo "There has been a successful run of the ${env.BRANCH_NAME} pipeline."
		    emailext to: "${TARGET_SUCCESS_EMAILS}",
			subject: "GO Pipeline success for ${env.BRANCH_NAME}",
			body: "There has been successful run of the ${env.BRANCH_NAME} pipeline. Please see: https://build.geneontology.io/job/pipeline-pipeline-raw-go-cam/job/${env.BRANCH_NAME}"
		}
	    }
	}
	// Let's let our internal people know if things change.
	changed {
	    echo "There has been a change in the ${env.BRANCH_NAME} pipeline."
	    emailext to: "${TARGET_ADMIN_EMAILS}",
		subject: "GO Pipeline change for ${env.BRANCH_NAME}",
		body: "There has been a pipeline status change in ${env.BRANCH_NAME}. Please see: https://build.geneontology.io/job/geneontology/job/pipeline-raw-go-cam/job/${env.BRANCH_NAME}"
	}
	// Let's let our internal people know if things go badly.
	failure {
	    echo "There has been a failure in the ${env.BRANCH_NAME} pipeline."
	    emailext to: "${TARGET_ADMIN_EMAILS}",
		subject: "GO Pipeline FAIL for ${env.BRANCH_NAME}",
		body: "There has been a pipeline failure in ${env.BRANCH_NAME}. Please see: https://build.geneontology.io/job/pipeline-raw-go-cam/job/${env.BRANCH_NAME}"
	}
    }
}

// Check that we do not affect public targets on non-mainline runs.
void watchdog() {
    if( BRANCH_NAME != 'master' && TARGET_BUCKET == 'go-data-product-experimental'){
	echo 'Only master can touch that target.'
	sh '`exit -1`'
    }else if( BRANCH_NAME != 'snapshot-post-fail' && TARGET_BUCKET == 'go-data-product-snapshot'){
	echo 'Only master can touch that target.'
	sh '`exit -1`'
    }else if( BRANCH_NAME != 'release' && TARGET_BUCKET == 'go-data-product-release'){
	echo 'Only master can touch that target.'
	sh '`exit -1`'
    }
}

// Reset and initialize skyhook base.
void initialize() {

    // Possibly protect against issues like #350 by making sure
    // $JOB_NAME is there and vaguely sane.
    if(JOB_NAME instanceof String && JOB_NAME.size() >= 3 ) {

	// Get a mount point ready
	sh 'mkdir -p $WORKSPACE/mnt || true'
	// Ninja in our file credentials from Jenkins.
	withCredentials([file(credentialsId: 'skyhook-private-key', variable: 'SKYHOOK_IDENTITY'), string(credentialsId: 'skyhook-machine-private', variable: 'SKYHOOK_MACHINE')]) {
	    // Try and ssh fuse skyhook onto our local system.
	    sh 'sshfs -o StrictHostKeyChecking=no -o IdentitiesOnly=true -o IdentityFile=$SKYHOOK_IDENTITY -o idmap=user skyhook@$SKYHOOK_MACHINE:/home/skyhook $WORKSPACE/mnt/'
	}
	// Remove anything we might have left around from
	// times past.
	sh 'rm -r -f $WORKSPACE/mnt/$JOB_NAME || true'
	// Rebuild directory structure.
	sh 'mkdir -p $WORKSPACE/mnt/$JOB_NAME/bin || true'
	// WARNING/BUG: needed for arachne to run at
	// this point.
	sh 'mkdir -p $WORKSPACE/mnt/$JOB_NAME/lib || true'
	sh 'mkdir -p $WORKSPACE/mnt/$JOB_NAME/products || true'
	sh 'mkdir -p $WORKSPACE/mnt/$JOB_NAME/products/ttl || true'
	sh 'mkdir -p $WORKSPACE/mnt/$JOB_NAME/products/json || true'
	sh 'mkdir -p $WORKSPACE/mnt/$JOB_NAME/products/blazegraph || true'
	sh 'mkdir -p $WORKSPACE/mnt/$JOB_NAME/products/upstream_and_raw_data || true'
	sh 'mkdir -p $WORKSPACE/mnt/$JOB_NAME/products/pages || true'
	sh 'mkdir -p $WORKSPACE/mnt/$JOB_NAME/products/solr || true'
	sh 'mkdir -p $WORKSPACE/mnt/$JOB_NAME/products/panther || true'
	sh 'mkdir -p $WORKSPACE/mnt/$JOB_NAME/products/gaferencer || true'
	sh 'mkdir -p $WORKSPACE/mnt/$JOB_NAME/metadata || true'
	sh 'mkdir -p $WORKSPACE/mnt/$JOB_NAME/annotations || true'
	sh 'mkdir -p $WORKSPACE/mnt/$JOB_NAME/ontology || true'
	sh 'mkdir -p $WORKSPACE/mnt/$JOB_NAME/reports || true'
	sh 'mkdir -p $WORKSPACE/mnt/$JOB_NAME/release_stats || true'
	// Tag the top to let the world know I was at least
	// here.
	sh 'echo "Runtime summary." > $WORKSPACE/mnt/$JOB_NAME/summary.txt'
	sh 'echo "" >> $WORKSPACE/mnt/$JOB_NAME/summary.txt'
	sh 'date >> $WORKSPACE/mnt/$JOB_NAME/summary.txt'
	sh 'echo "" >> $WORKSPACE/mnt/$JOB_NAME/summary.txt'
	sh 'echo "Release notes: https://github.com/geneontology/go-site/tree/master/releases" >> $WORKSPACE/mnt/$JOB_NAME/summary.txt'
	sh 'echo "Branch: $JOB_NAME" >> $WORKSPACE/mnt/$JOB_NAME/summary.txt'
	sh 'echo "Start day: $START_DAY" >> $WORKSPACE/mnt/$JOB_NAME/summary.txt'
	sh 'echo "Start date: $START_DATE" >> $WORKSPACE/mnt/$JOB_NAME/summary.txt'
	sh 'echo "$START_DAY" > $WORKSPACE/mnt/$JOB_NAME/metadata/dow.txt'
	sh 'echo "$START_DATE" > $WORKSPACE/mnt/$JOB_NAME/metadata/date.txt'

	sh 'echo "Official release date: metadata/release-date.json" >> $WORKSPACE/mnt/$JOB_NAME/summary.txt'
	sh 'echo "Official Zenodo archive DOI: metadata/release-archive-doi.json" >> $WORKSPACE/mnt/$JOB_NAME/summary.txt'
	sh 'echo "TODO: Note software versions." >> $WORKSPACE/mnt/$JOB_NAME/summary.txt'
	// TODO: This should be wrapped in exception
	// handling. In fact, this whole thing should be.
	sh 'fusermount -u $WORKSPACE/mnt/ || true'
    }else{
	sh 'echo "HOW DID THIS EVEN HAPPEN?"'
    }
}
