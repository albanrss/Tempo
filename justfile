[group('dev')]
clean:
    flutter clean

[group('dev')]
test: clean
    flutter test

[group('dev')]
run-debug: clean
    flutter run

[group('release')]
build-apk: clean
    flutter build apk --release

[group('release')]
run-release: clean
    flutter run --release
