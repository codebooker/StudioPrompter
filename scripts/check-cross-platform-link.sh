#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
folder="$PWD/.build/cross-platform-link"
mkdir -p "$folder"
swiftc -emit-library -emit-module -module-name PrompterCore Sources/PrompterCore/*.swift -o "$folder/libPrompterCore.dylib"
swiftc -emit-library -emit-module -module-name PrompterLink -I "$folder" -L "$folder" -lPrompterCore Sources/PrompterLink/*.swift -o "$folder/libPrompterLink.dylib"
swiftc -I "$folder" -L "$folder" -lPrompterCore -lPrompterLink -Xlinker -rpath -Xlinker "$folder" Tests/CrossPlatformLink/main.swift -o "$folder/native-fixture"
for artifact in bcprov bcutil bctls; do
  curl -fsSL "https://repo.maven.apache.org/maven2/org/bouncycastle/${artifact}-jdk18on/1.85/${artifact}-jdk18on-1.85.jar" -o "$folder/${artifact}.jar"
done
curl -fsSL https://repo.maven.apache.org/maven2/org/json/json/20240303/json-20240303.jar -o "$folder/json.jar"
curl -fsSL https://repo.maven.apache.org/maven2/junit/junit/4.13.2/junit-4.13.2.jar -o "$folder/junit.jar"
curl -fsSL https://repo.maven.apache.org/maven2/org/hamcrest/hamcrest-core/1.3/hamcrest-core-1.3.jar -o "$folder/hamcrest.jar"
"${STUDIO_JAVA_BIN:-/usr/bin}/javac" -cp "$folder/*" -d "$folder" \
  android/app/src/main/java/co/codebooker/studioprompter/companion/{Protocol,PskTransport,RemoteMotion}.java \
  android/app/src/test/java/co/codebooker/studioprompter/companion/*.java
"${STUDIO_JAVA_BIN:-/usr/bin}/java" -Dstudio.repo="$PWD" -Dstudio.fixture="$folder/native-fixture" -cp "$folder/*:$folder" \
  org.junit.runner.JUnitCore co.codebooker.studioprompter.companion.ProtocolTest co.codebooker.studioprompter.companion.InteropTest

# Verify the opposite direction with the iPad's actual Apple connection code.
node desktop/fetch-node.mjs
swiftc -I "$folder" -L "$folder" -lPrompterCore -lPrompterLink -Xlinker -rpath -Xlinker "$folder" \
  Tests/CrossPlatformLink/Client.swift -o "$folder/apple-client"
STUDIO_APPLE_CLIENT="$folder/apple-client" node --test desktop/test/apple-client.test.cjs
