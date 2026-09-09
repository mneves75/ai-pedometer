# Coding Style and Naming

## Swift Language
- Swift 6.2 with complete strict concurrency; warnings are treated as errors. Both are set in
  `project.yml`, not in the xcconfigs, which only carry `SWIFT_COMPILATION_MODE` and the optional
  `Local.xcconfig` include.

## Formatting
No enforced formatter — match the style of the surrounding file.

## Localization
- Add strings to `Shared/Resources/Localizable.xcstrings` with clear comments.
