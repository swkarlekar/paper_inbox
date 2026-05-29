.PHONY: build test typecheck app

typecheck:
	swiftc -typecheck -module-cache-path .build/module-cache -Xcc -fmodules-cache-path=.build/clang-module-cache -I Sources/SQLiteShim/include Sources/PaperInboxCore/Models/*.swift Sources/PaperInboxCore/Utilities/*.swift Sources/PaperInboxCore/Services/*.swift Sources/PaperInboxCore/Database/*.swift
	mkdir -p .build/typecheck
	swiftc -emit-module -emit-module-path .build/typecheck/PaperInboxCore.swiftmodule -module-name PaperInboxCore -parse-as-library -module-cache-path .build/module-cache -Xcc -fmodules-cache-path=.build/clang-module-cache -I Sources/SQLiteShim/include Sources/PaperInboxCore/Models/*.swift Sources/PaperInboxCore/Utilities/*.swift Sources/PaperInboxCore/Services/*.swift Sources/PaperInboxCore/Database/*.swift
	swiftc -typecheck -module-cache-path .build/module-cache -Xcc -fmodules-cache-path=.build/clang-module-cache -I .build/typecheck -I Sources/SQLiteShim/include Sources/PaperInbox/*.swift

app:
	Scripts/build-app-bundle.sh

build:
	swift build

test:
	swift test
