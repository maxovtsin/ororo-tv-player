
.PHONY : log install_buck build watch message targets audit debug test xcode_tests clean project audit

log:
	echo "Make"

install_buck:
	brew tap facebook/fb
	brew install buck

update_carthage:
	carthage bootstrap --cache-builds --use-ssh

build:
	buck build //Ororo-Player:OroroPlayer

debug:
	buck install //App:ExampleApp --run --simulator-name 'iPhone XS'

targets:
	buck targets //...

clean:
	rm -rf **/*.xcworkspace
	rm -rf **/*.xcodeproj
	rm -rf buck-out

kill_xcode:
	killall Xcode || true
	killall Simulator || true

project: clean
	buck project //Ororo-Player:OroroPlayer --ide xcode
	open Ororo-Player/Ororo-Player.xcworkspace