import Foundation
import AuthenticationServices

/// 账户：仅 Sign in with Apple + 手机号（验证码走短信网关，此处给出接口）。
/// 全功能免费，无订阅无内购。
final class AuthService: NSObject, ObservableObject {
    static let shared = AuthService()
    @Published var isSignedIn = false
    @Published var accountName = "跑者"

    private let appleIDProvider = ASAuthorizationAppleIDProvider()

    func signInWithApple(presentation: ASAuthorizationControllerPresentationContextProviding) {
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = presentation
        controller.performRequests()
    }

    /// 发送短信验证码（接入阿里云/腾讯云 SMS 时在此实现）
    func sendSMSCode(phone: String) async throws {
        // TODO: 对接短信网关；本地开发直接固定 123456
        try await Task.sleep(nanoseconds: 300_000_000)
    }

    func verifySMSCode(phone: String, code: String) async -> Bool {
        // TODO: 服务端校验；本地开发固定 123456
        try? await Task.sleep(nanoseconds: 300_000_000)
        if code == "123456" {
            await MainActor.run {
                self.isSignedIn = true
                self.accountName = String(phone.suffix(4))
            }
            return true
        }
        return false
    }

    func signOut() { isSignedIn = false }
}

extension AuthService: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
            accountName = credential.fullName?.givenName ?? "跑者"
            isSignedIn = true
            // identityToken 可发送至自有服务端校验
            _ = credential.identityToken
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        #if DEBUG
        print("[Auth] Sign in with Apple failed: \(error)")
        #endif
    }
}
