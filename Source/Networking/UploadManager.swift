//
//  UploadManager.swift
//  PPPC Utility
//
//  Created by Kyle Hammond on 11/3/23.
//  Copyright © 2023 Jamf. All rights reserved.
//

import Foundation
import os.log

struct UploadManager {
	let serverURL: String

	struct VerificationInfo {
		let mustSign: Bool
		let organization: String
	}

	enum VerificationError: Error {
		case anyError(String)
	}

	func verifyConnection(authManager: NetworkAuthManager, completionHandler: @escaping (Result<VerificationInfo, VerificationError>) -> Void) {
		os_log("Checking connection to Jamf Pro server", type: .default)

		Task {
			let networking = JamfProAPIClient(serverUrlString: serverURL, tokenManager: authManager)
			let result: Result<VerificationInfo, VerificationError>

			do {
				let version = try await networking.getJamfProVersion()

				// Must sign if Jamf Pro is less than v10.7.1
				let mustSign = (version.semantic() < SemanticVersion(major: 10, minor: 7, patch: 1))

				let orgName = try await networking.getOrganizationName()

				result = .success(VerificationInfo(mustSign: mustSign, organization: orgName))
			} catch is AuthError {
				os_log("Invalid credentials.", type: .default)
				result = .failure(VerificationError.anyError("Invalid credentials."))
			} catch {
				os_log("Jamf Pro server is unavailable.", type: .default)
				result = .failure(VerificationError.anyError("Jamf Pro server is unavailable."))
			}

			completionHandler(result)
		}
	}

	func upload(profile: TCCProfile, authMgr: NetworkAuthManager, siteInfo: (String, String)?, signingIdentity: SigningIdentity?, completionHandler: @escaping (Error?) -> Void) {
		os_log("Uploading profile: %{public}s", profile.displayName)

		let networking = JamfProAPIClient(serverUrlString: serverURL, tokenManager: authMgr)
		Task {
			let success: Error?
			var identity: SecIdentity?
			if let signingIdentity = signingIdentity {
				os_log("Signing profile with \(signingIdentity.displayName)")
				identity = signingIdentity.reference
			}

			do {
				let profileData = try profile.jamfProAPIData(signingIdentity: identity, site: siteInfo)

				_ = try await networking.upload(computerConfigProfile: profileData)

				success = nil
				os_log("Uploaded successfully")
			} catch {
				os_log("Error creating or uploading profile: %s", type: .error, error.localizedDescription)
				success = error
			}

			DispatchQueue.main.async {
				completionHandler(success)
			}
		}
	}
}
