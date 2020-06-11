#!/bin/bash

interfaces=(\
j17 \
j21 \
j22 \
j23 \
j24 \
)

testcases=(
tb1 \
tb2 \
tb3 \
tb4 \
tb5 \
tb6 \
tb7 \
tb8 \
tb9 \
)

################################################################################
# Generate the manual test YAMLs for the ethernet interfaces
################################################################################
pushd manual/se
for interface in "${interfaces[@]}" ; do
	for testcase in "${testcases[@]}" ; do
		newtestcase=${testcase}-${interface}
		cp ${testcase}.yaml ${newtestcase}.yaml
		sed -e "s/${testcase^^}/${newtestcase^^}/g" -i ${newtestcase}.yaml

		newtestcase=${newtestcase}-mtu1508
		cp ${testcase}.yaml ${newtestcase}.yaml
		sed -e "s/${testcase^^}/${newtestcase^^}/g" -i ${newtestcase}.yaml
	done
done
popd

################################################################################
# Generate individual test plans for the TB ethernet tests
# using the se-tb-template.yaml template
################################################################################
pushd plans
# generate se-tb-<interface>.yaml
for interface in "${interfaces[@]}" ; do

	newplan=se-tb-${interface}.yaml
	cp se-tb-template.yaml ${newplan}
	sed -e "s/jnn/${interface}/g" -i ${newplan}

done
popd


################################################################################
# generate se-tb.yaml
# all manual/se/tb*.yaml files, except tb1-9
################################################################################
plan=plans/se-tb.yaml
cp plans/se-template.yaml ${plan}

sed -e "s/se-template/se-tb/g" -i ${plan}
sed -e "s/Scheider Electric template/Scheider Electric TB Test Plan/g" -i ${plan}
# TODO - describe what the TB test plan is"

testcases=($(ls manual/se/tb[1-9]?.yaml))
for testcase in "${testcases[@]}" ; do
	echo "    -path: ${testcase}" >> ${plan}
	echo "      repository: https://github.com/omnium21/test-definitions.git" >> ${plan}
	echo "      branch: linaro" >> ${plan}
done

################################################################################
# generate se-tc.yaml
# all manual/se/tc*.yaml files
################################################################################
plan=plans/se-tc.yaml
cp plans/se-template.yaml ${plan}

sed -e "s/se-template/se-tc/g" -i ${plan}
sed -e "s/Scheider Electric template/Scheider Electric TC Test Plan/g" -i ${plan}
# TODO - describe what the TC test plan is"

testcases=($(ls manual/se/tc*.yaml))
for testcase in "${testcases[@]}" ; do
	echo "    -path: ${testcase}" >> ${plan}
	echo "      repository: https://github.com/omnium21/test-definitions.git" >> ${plan}
	echo "      branch: linaro" >> ${plan}
done

################################################################################
# generate se-others.yaml
# all manual/se/*.yaml files not included in se-tb and te-tc plans
################################################################################
plan=plans/se-others.yaml
cp plans/se-template.yaml ${plan}

sed -e "s/se-template/se-others/g" -i ${plan}
sed -e "s/Scheider Electric template/Scheider Electric Misc Manual Test Plan/g" -i ${plan}
# TODO - describe what this test plan is"

testcases=($(ls manual/se/*.yaml | grep -v t[bc][0-9]))
for testcase in "${testcases[@]}" ; do
	echo "    - path: ${testcase}" >> ${plan}
	echo "      repository: https://github.com/omnium21/test-definitions.git" >> ${plan}
	echo "      branch: linaro" >> ${plan}
done

################################################################################
# generate se-all.yaml
# everything in se-auto.yaml, and all yamls in manual/se
################################################################################
plan=plans/se-all-tests.yaml
cp plans/se-auto.yaml ${plan}

sed -e "s/se-auto/se-all-tests/g" -i ${plan}
sed -e "s/Scheider Electric Automated Test Plan/Scheider Electric Test Plan describing all manual and automated tests performed when making a release/g" -i ${plan}
# TODO - describe what this test plan is"

echo "  manual:" >> ${plan}
testcases=($(ls manual/se/*.yaml | grep -v tb[0-9]-j | sort -V))

for testcase in "${testcases[@]}" ; do
	echo "    - path: ${testcase}" >> ${plan}
	echo "      repository: https://github.com/omnium21/test-definitions.git" >> ${plan}
	echo "      branch: linaro" >> ${plan}
done


################################################################################
# Generate the HTML Test Plan
################################################################################
pushd plans
plan=se-all-tests.yaml
sed -e "s/Metadata/Schneider Electric Test Plan/g" -i templates/testplan_v2.html
python2 ./testplan2html.py -f ${plan} -i -s
popd
