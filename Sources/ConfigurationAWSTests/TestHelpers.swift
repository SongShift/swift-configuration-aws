//
//  TestHelpers.swift
//
//  Created by Ben Rosen on 2/22/26.
//  Copyright © 2026 SongShift, LLC. All rights reserved.
//

import Configuration

func configKey(_ dotSeparated: String) -> AbsoluteConfigKey {
    AbsoluteConfigKey(dotSeparated.split(separator: ".").map(String.init))
}

enum TestError: Error {
    case simulatedFailure
}
