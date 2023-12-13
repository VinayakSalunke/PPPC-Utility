//
//  NetworkAuthManagerTests.swift
//  PPPC UtilityTests
//
//  MIT License
//
//  Copyright (c) 2022 Jamf Software
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import Foundation
import XCTest

@testable import PPPC_Utility

/// Fake networking class for testing.  No actual network was used in the making of this test.
class MockNetworking: Networking {
    var errorToThrow: Error?

    init(tokenManager: NetworkAuthManager) {
        super.init(serverUrlString: "https://example.com", tokenManager: tokenManager)
    }

    override func getBearerToken(authInfo: AuthenticationInfo) async throws -> Token {
        if let error = errorToThrow {
            throw error
        }

		let formatter = ISO8601DateFormatter()
		formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		let expiration = try XCTUnwrap(formatter.date(from: "2950-06-22T22:05:58.81Z"))

		return Token(value: "xyz", expiresAt: expiration)
    }
}

class NetworkAuthManagerTests: XCTestCase {
    func testValidToken() async throws {
        // given
        let authManager = NetworkAuthManager(username: "test", password: "none")
        let networking = MockNetworking(tokenManager: authManager)

        // when
        let token = try await authManager.validToken(networking: networking)

        // then
        XCTAssertEqual(token.value, "xyz")
        XCTAssertTrue(token.isValid)
    }

    func testValidTokenNetworkFailure() async throws {
        // given
        let authManager = NetworkAuthManager(username: "test", password: "none")
        let networking = MockNetworking(tokenManager: authManager)
        networking.errorToThrow = NetworkingError.serverResponse(500, "Bad server")

        // when
        do {
            _ = try await authManager.validToken(networking: networking)
            XCTFail("Expected to throw from `validToken` call")
        } catch {
            // then
            XCTAssertEqual(error as? NetworkingError, NetworkingError.serverResponse(500, "Bad server"))
        }
    }

    func testValidTokenBearerAuthNotSupported() async throws {
        // given
        let authManager = NetworkAuthManager(username: "test", password: "none")
        let networking = MockNetworking(tokenManager: authManager)
        networking.errorToThrow = NetworkingError.serverResponse(404, "No such page")

        // default is that bearer auth is supported.
        let firstCheckBearerAuthSupported = await authManager.bearerAuthSupported()
        XCTAssertTrue(firstCheckBearerAuthSupported)

        // when
        do {
            _ = try await authManager.validToken(networking: networking)
            XCTFail("Expected to throw from `validToken` call")
        } catch {
            // then - should throw a `bearerAuthNotSupported` error
            XCTAssertEqual(error as? AuthError, AuthError.bearerAuthNotSupported)
        }

        // The authManager should now know that bearer auth is not supported
        let secondCheckBearerAuthSupported = await authManager.bearerAuthSupported()
        XCTAssertFalse(secondCheckBearerAuthSupported)
    }

    func testValidTokenInvalidUsernamePassword() async throws {
        // given
        let authManager = NetworkAuthManager(username: "test", password: "none")
        let networking = MockNetworking(tokenManager: authManager)
        networking.errorToThrow = NetworkingError.serverResponse(401, "Not authorized")

        // when
        do {
            _ = try await authManager.validToken(networking: networking)
            XCTFail("Expected to throw from `validToken` call")
        } catch {
            // then - should throw a `invalidUsernamePassword` error
            XCTAssertEqual(error as? AuthError, AuthError.invalidUsernamePassword)
        }
    }

    func testBasicAuthString() throws {
        // given
        let authManager = NetworkAuthManager(username: "test", password: "none")

        // when
        let actual = try authManager.basicAuthString()

        // then
        XCTAssertEqual(actual, "dGVzdDpub25l")
    }

    func testBasicAuthStringEmptyUsername() throws {
        // given
        let authManager = NetworkAuthManager(username: "", password: "none")

        // when
        do {
            _ = try authManager.basicAuthString()
            XCTFail("Expected to throw from `basicAuthString` call")
        } catch {
            // then - should throw a `invalidUsernamePassword` error
            XCTAssertEqual(error as? AuthError, AuthError.invalidUsernamePassword)
        }
    }

    func testBasicAuthStringEmptyPassword() throws {
        // given
        let authManager = NetworkAuthManager(username: "mine", password: "")

        // when
        do {
            _ = try authManager.basicAuthString()
            XCTFail("Expected to throw from `basicAuthString` call")
        } catch {
            // then - should throw a `invalidUsernamePassword` error
            XCTAssertEqual(error as? AuthError, AuthError.invalidUsernamePassword)
        }
    }
}
