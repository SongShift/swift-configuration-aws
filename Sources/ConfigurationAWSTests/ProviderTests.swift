//
//  ProviderTests.swift
//  swift-configuration-aws
//
//  Created by Ben on 11/16/25.
//

import ConfigurationTesting

@Test func compat() async throws {
    try await ProviderCompatTest(provider: provider).runTest()
}
