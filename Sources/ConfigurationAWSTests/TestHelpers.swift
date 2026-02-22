import Configuration

func configKey(_ dotSeparated: String) -> AbsoluteConfigKey {
    AbsoluteConfigKey(dotSeparated.split(separator: ".").map(String.init))
}

enum TestError: Error {
    case simulatedFailure
}
