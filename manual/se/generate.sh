interfaces=(\
j17 \
j21 \
j22 \
j23 \
j24 \
)

files=(
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

for interface in "${interfaces[@]}" ; do
	for file in "${files[@]}" ; do
		newfile=${file}-${interface}
		cp ${file}.yaml ${newfile}.yaml
		sed -e "s/${file^^}/${newfile^^}/g" -i ${newfile}.yaml

		newfile=${newfile}-mtu1508
		cp ${file}.yaml ${newfile}.yaml
		sed -e "s/${file^^}/${newfile^^}/g" -i ${newfile}.yaml
	done
done
