[group('dev')]
clean:
    flutter clean

[group('dev')]
test: clean
    flutter test

[group('dev')]
run-debug: clean
    flutter run

[group('dev')]
format:
    dart format --page-width 95 .

[group('dev')]
analyze:
    flutter analyze

[group('release')]
build-apk: clean
    flutter build apk --release

[group('release')]
run-release: clean
    flutter run --release
