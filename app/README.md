## Build
depends on Go 1.20.14, OpenJDK 17, Gradle 8.2, Android SDK 31 and NDK 21.4.7075529
```

go install golang.org/x/mobile/cmd/gomobile@7c4916698cc93475ebfea76748ee0faba2deb2a5
go install golang.org/x/mobile/cmd/gobind@7c4916698cc93475ebfea76748ee0faba2deb2a5
gomobile init
cp go.mod android.mod
cp go.sum android.sum
GOFLAGS="-modfile=$PWD/android.mod" go get -v golang.org/x/mobile/bind@7c4916698cc93475ebfea76748ee0faba2deb2a5
GOFLAGS="-modfile=$PWD/android.mod" gomobile bind -target android -androidapi 16 -o app/app/libs/openp2p.aar ./core
if [[ $? -ne 0 ]]; then
    echo "build error"
    exit 9
fi
echo "build ok"
echo "AAR and sources JAR written to app/app/libs"

edit app/app/build.gradle 
```
signingConfigs {
        release {
            storeFile file('YOUR-JKS-PATH')
            storePassword 'YOUR-PASSWORD'
            keyAlias 'openp2p.keys'
            keyPassword 'YOUR-PASSWORD'
        }
    }
```
cd app
./gradlew assembleRelease bundleRelease

```
