#!/bin/bash
# Copyright (C) 2023 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This command is expected to be executed with: atest hoststubgen-invoke-test

set -e # Exit when any command files

# This script runs HostStubGen directly with various arguments and make sure
# the tool behaves in the expected way.


echo "# Listing files in the test environment"
ls -lR

echo "# Dumping the environment variables"
env

# Set up the constants and variables

# Bazel sets $TEST_TMPDIR.
export TEMP=$TEST_TMPDIR

if [[ "$TEMP" == "" ]] ; then
  TEMP=./tmp
  mkdir -p $TEMP
fi

cleanup_temp() {
  rm -fr $TEMP/*
}

cleanup_temp

INJAR=hoststubgen-test-tiny-framework.jar
OUTJAR=$TEMP/host.jar

ANNOTATION_FILTER=$TEMP/annotation-filter.txt
POLICY_FILE=$TEMP/policy-file.txt

HOSTSTUBGEN_OUT=$TEMP/output.txt

EXTRA_ARGS=""

# Because of `set -e`, we can't return non-zero from functions, so we store
# HostStubGen result in it.
HOSTSTUBGEN_RC=0

# Note, because the build rule will only install hoststubgen.jar, but not the wrapper script,
# we need to execute it manually with the java command.
hoststubgen() {
  echo "Running hoststubgen with: $*"
  java -jar ./hoststubgen.jar "$@"
}

run_hoststubgen() {
  local test_name="$1"
  local annotation_filter="$2"
  local policy="$3"

  echo "# Test: $test_name"

  cleanup_temp

  local filter_arg=""
  local policy_arg=""

  if [[ "$annotation_filter" != "" ]] ; then
    echo "$annotation_filter" > $ANNOTATION_FILTER
    filter_arg="--annotation-allowed-classes-file $ANNOTATION_FILTER"
    echo "=== filter ==="
    cat $ANNOTATION_FILTER
  fi

  if [[ "$policy" != "" ]] ; then
    echo "$policy" > $POLICY_FILE
    policy_arg="--policy-override-file $POLICY_FILE"
    echo "=== policy ==="
    cat $POLICY_FILE
  fi

  local out_arg=""

  if [[ "$OUTJAR" != "" ]] ; then
    out_arg="--out-jar $OUTJAR"
  fi

  hoststubgen \
      --debug \
      --in-jar $INJAR \
      $out_arg \
      --keep-annotation \
          android.hosttest.annotation.HostSideTestKeep \
      --keep-class-annotation \
          android.hosttest.annotation.HostSideTestWholeClassKeep \
      --throw-annotation \
          android.hosttest.annotation.HostSideTestThrow \
      --remove-annotation \
          android.hosttest.annotation.HostSideTestRemove \
      --substitute-annotation \
          android.hosttest.annotation.HostSideTestSubstitute \
      --redirect-annotation \
          android.hosttest.annotation.HostSideTestRedirect \
      --redirection-class-annotation \
          android.hosttest.annotation.HostSideTestRedirectionClass \
      --class-load-hook-annotation \
          android.hosttest.annotation.HostSideTestClassLoadHook \
      --keep-static-initializer-annotation \
          android.hosttest.annotation.HostSideTestStaticInitializerKeep \
      --partially-allowed-annotation \
          android.hosttest.annotation.HostSideTestPartiallyAllowlisted \
      $filter_arg \
      $policy_arg \
      $EXTRA_ARGS \
      |& tee $HOSTSTUBGEN_OUT
  HOSTSTUBGEN_RC=${PIPESTATUS[0]}
  echo "HostStubGen exited with $HOSTSTUBGEN_RC"
  return 0
}

assert_file_generated() {
  local file="$1"
  if [[ "$file" == "" ]] ; then
    if [[ -f "$file" ]] ; then
      echo "HostStubGen shouldn't have generated $file"
      return 1
    fi
  else
    if ! [[ -f "$file" ]] ; then
      echo "HostStubGen didn't generate $file"
      return 1
    fi
  fi
}

run_hoststubgen_for_success() {
  local test_name="$1"
  run_hoststubgen "$@"

  if (( $HOSTSTUBGEN_RC != 0 )) ; then
    echo "HostStubGen expected to finish successfully, but failed with $HOSTSTUBGEN_RC: Test=$test_name"
    return 1
  fi

  assert_file_generated "$STUB"
  assert_file_generated "$IMPL"
}

run_hoststubgen_for_failure() {
  local test_name="$1"
  local expected_error_message="$2"
  shift 2

  run_hoststubgen "$test_name" "$@"

  if (( $HOSTSTUBGEN_RC == 0 )) ; then
    echo "HostStubGen expected to fail, but it didn't fail. Test=$test_name"
    return 1
  fi

  # The output should contain the expected message. (note we se fgrep here.)
  grep -Fq "$expected_error_message" $HOSTSTUBGEN_OUT
}

# Start the tests...

# These classes require special care, so let's delete them in most tests...
DELETE_PARTIAL_ANNOTATION_CLASSESS='
class com.android.hoststubgen.test.tinyframework.TinyFrameworkPartiallyAllowlisted$PartiallyAllowlisted remove
class com.android.hoststubgen.test.tinyframework.TinyFrameworkPartiallyAllowlisted$PartialWithWholeClass_bad remove
class com.android.hoststubgen.test.tinyframework.TinyFrameworkPartiallyAllowlisted$PartiallyAllowlistedWithoutAnnot_bad remove
'

# Pass "" as a filter to _not_ add `--annotation-allowed-classes-file`.
run_hoststubgen_for_success "No annotation filter" "" "$DELETE_PARTIAL_ANNOTATION_CLASSESS"

# Now, we use " ", so we do add `--annotation-allowed-classes-file`.
run_hoststubgen_for_failure "No classes are allowed to have annotations" \
    "not allowed to have Ravenwood annotations" \
    " " "$DELETE_PARTIAL_ANNOTATION_CLASSESS"

run_hoststubgen_for_success "All classes allowed (wildcard)" \
    "
* # Allow all classes
" "$DELETE_PARTIAL_ANNOTATION_CLASSESS"

run_hoststubgen_for_failure "All classes disallowed (wildcard)" \
    "not allowed to have Ravenwood annotations" \
    "
!* # Disallow all classes
" "$DELETE_PARTIAL_ANNOTATION_CLASSESS"

run_hoststubgen_for_failure "Some classes not allowed (1)" \
    "not allowed to have Ravenwood annotations" \
    "
android.hosttest.*
com.android.hoststubgen.*
com.supported.*
" "$DELETE_PARTIAL_ANNOTATION_CLASSESS"

run_hoststubgen_for_failure "Some classes not allowed (2)" \
    "not allowed to have Ravenwood annotations" \
    "
android.hosttest.*
com.android.hoststubgen.*
com.unsupported.*
" "$DELETE_PARTIAL_ANNOTATION_CLASSESS"

run_hoststubgen_for_success "All classes allowed (package wildcard)" \
    "
android.hosttest.*
com.android.hoststubgen.*
com.supported.*
com.unsupported.*
" "$DELETE_PARTIAL_ANNOTATION_CLASSESS"

run_hoststubgen_for_failure "One specific class disallowed" \
    "TinyFrameworkAnnotations is not allowed to have Ravenwood annotations" \
    "
!com.android.hoststubgen.test.tinyframework.TinyFrameworkAnnotations
* # All other classes allowed
" "$DELETE_PARTIAL_ANNOTATION_CLASSESS"

run_hoststubgen_for_success "One specific class disallowed, but it doesn't use annotations" \
    "
!com.android.hoststubgen.test.tinyframework.TinyFrameworkForTextPolicy
* # All other classes allowed
" "$DELETE_PARTIAL_ANNOTATION_CLASSESS"

OUTJAR="" run_hoststubgen_for_success "No output generation" "" "$DELETE_PARTIAL_ANNOTATION_CLASSESS"

EXTRA_ARGS="--in-jar abc" run_hoststubgen_for_failure "Duplicate arg" \
    "Duplicate or conflicting argument found: --in-jar" \
    ""

# ---------------------------------------------------------------------------------------------
# Tests for "partially-allowlisted".
# ---------------------------------------------------------------------------------------------

# Allowlist used by hoststubgen-test-tiny-test.
ALLOWLIST='
com.android.hoststubgen.test.tinyframework.*
com.supported.*
com.unsupported.*
!*
'

run_hoststubgen_for_success 'The settings used by hoststubgen-test-tiny-test' \
    "$ALLOWLIST" \
    '
class com.android.hoststubgen.test.tinyframework.TinyFrameworkPartiallyAllowlisted$PartiallyAllowlisted allow-annotation
    method foo2 allow-annotation

class com.android.hoststubgen.test.tinyframework.TinyFrameworkPartiallyAllowlisted$PartialWithWholeClass_bad remove
class com.android.hoststubgen.test.tinyframework.TinyFrameworkPartiallyAllowlisted$PartiallyAllowlistedWithoutAnnot_bad remove
'

run_hoststubgen_for_failure 'PartiallyAllowlisted does not have allow-annotation' \
    "PartiallyAllowlisted has annotation android.hosttest.annotation.HostSideTestPartiallyAllowlisted, but" \
    "$ALLOWLIST" \
    '
#class com.android.hoststubgen.test.tinyframework.TinyFrameworkPartiallyAllowlisted$PartiallyAllowlisted allow-annotation
#    method foo2 allow-annotation

class com.android.hoststubgen.test.tinyframework.TinyFrameworkPartiallyAllowlisted$PartialWithWholeClass_bad remove
class com.android.hoststubgen.test.tinyframework.TinyFrameworkPartiallyAllowlisted$PartiallyAllowlistedWithoutAnnot_bad remove
'


run_hoststubgen_for_failure 'PartiallyAllowlisted.foo2 does not have allow-annotation' \
    "foo2(I)I is not allowed to have Ravenwood annotations. (Class is partially allowlisted.)" \
    "$ALLOWLIST" \
    '
class com.android.hoststubgen.test.tinyframework.TinyFrameworkPartiallyAllowlisted$PartiallyAllowlisted allow-annotation
#    method foo2 allow-annotation

class com.android.hoststubgen.test.tinyframework.TinyFrameworkPartiallyAllowlisted$PartialWithWholeClass_bad remove
class com.android.hoststubgen.test.tinyframework.TinyFrameworkPartiallyAllowlisted$PartiallyAllowlistedWithoutAnnot_bad remove
'

run_hoststubgen_for_failure 'Partially-allowlisted classes cannot have class-wide policies' \
    "PartialWithWholeClass_bad has class wide annotation android.hosttest.annotation.HostSideTestWholeClassKeep" \
    "$ALLOWLIST" \
    '
class com.android.hoststubgen.test.tinyframework.TinyFrameworkPartiallyAllowlisted$PartiallyAllowlisted allow-annotation
    method foo2 allow-annotation

# Now with allow-annotation
class com.android.hoststubgen.test.tinyframework.TinyFrameworkPartiallyAllowlisted$PartialWithWholeClass_bad allow-annotation

class com.android.hoststubgen.test.tinyframework.TinyFrameworkPartiallyAllowlisted$PartiallyAllowlistedWithoutAnnot_bad remove
'

run_hoststubgen_for_failure 'Partially-allowlisted classes cannot have class-wide policies' \
    "PartiallyAllowlistedWithoutAnnot_bad must have android.hosttest.annotation.HostSideTestPartiallyAllowlisted" \
    "$ALLOWLIST" \
    '
class com.android.hoststubgen.test.tinyframework.TinyFrameworkPartiallyAllowlisted$PartiallyAllowlisted allow-annotation
    method foo2 allow-annotation
class com.android.hoststubgen.test.tinyframework.TinyFrameworkPartiallyAllowlisted$PartialWithWholeClass_bad remove

# Now with allow-annotation
class com.android.hoststubgen.test.tinyframework.TinyFrameworkPartiallyAllowlisted$PartiallyAllowlistedWithoutAnnot_bad allow-annotation
'

run_hoststubgen_for_success 'The settings used by hoststubgen-test-tiny-test' \
    "$ALLOWLIST" \
    '
class com.android.hoststubgen.test.tinyframework.TinyFrameworkPartiallyAllowlisted$PartiallyAllowlisted allow-annotation
    method foo2 allow-annotation
class com.android.hoststubgen.test.tinyframework.TinyFrameworkPartiallyAllowlisted$PartialWithWholeClass_bad remove
class com.android.hoststubgen.test.tinyframework.TinyFrameworkPartiallyAllowlisted$PartiallyAllowlistedWithoutAnnot_bad remove

# NoAnnotations has no annotations at all. Setting "allow-annotation" to it is okay even though
# it does not have an @HostSideTestPartiallyAllowlisted, because it does nott have any other annotations anyway.
class com.android.hoststubgen.test.tinyframework.TinyFrameworkPartiallyAllowlisted$NoAnnotations allow-annotation
'

echo "All tests passed"
exit 0
