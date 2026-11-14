import Foundation
import OroroCore
import OroroFeatures
import Testing

@Suite @MainActor struct SignInViewModelTests {
    private func make(_ signIn: @escaping (String, String) async throws -> Void = { _, _ in }) -> SignInViewModel {
        let model = SignInViewModel(signIn: signIn)
        model.email = "a@b.co"
        model.password = "pw"
        return model
    }

    @Test func cannotSubmitEmptyOrInvalid() {
        let model = SignInViewModel(signIn: { _, _ in })
        #expect(!model.canSubmit)
        model.email = "a@b.co"
        #expect(!model.canSubmit)
        model.password = "pw"
        #expect(model.canSubmit)
        model.email = "   "
        #expect(!model.canSubmit)
        model.email = "no-at-sign"
        #expect(!model.canSubmit)
    }

    @Test func trimsEmail() async {
        var received: (String, String)?
        let model = make { received = ($0, $1) }
        model.email = "  a@b.co \n"
        await model.submit()
        #expect(received?.0 == "a@b.co")
        #expect(received?.1 == "pw")
    }

    @Test func successClearsError() async {
        var fail = true
        let model = make { _, _ in if fail { throw APIError.unauthorized } }
        await model.submit()
        #expect(model.error == .wrongCredentials)
        fail = false
        await model.submit()
        #expect(model.error == nil)
    }

    @Test func successClearsPassword() async {
        let model = make()
        await model.submit()
        #expect(model.password.isEmpty)
    }

    @Test func failureKeepsPasswordAndClearsErrorAtStart() async {
        var fail = true
        var errorDuringSecond: SignInViewModel.Message?
        var ref: SignInViewModel?
        let model = make { _, _ in
            if fail { throw APIError.offline }
            errorDuringSecond = ref?.error
        }
        ref = model
        await model.submit()
        #expect(model.password == "pw")
        fail = false
        await model.submit()
        #expect(errorDuringSecond == nil)
    }

    @Test func mapsUnauthorized() async {
        let model = make { _, _ in throw APIError.unauthorized }
        await model.submit()
        #expect(model.error == .wrongCredentials)
    }

    @Test func mapsOffline() async {
        let model = make { _, _ in throw APIError.offline }
        await model.submit()
        #expect(model.error == .offline)
    }

    @Test func mapsOtherToServer() async {
        for failure in [APIError.server(status: 0), .server(status: 500), .decoding, .notFound] {
            let model = make { _, _ in throw failure }
            await model.submit()
            #expect(model.error == .server)
        }
        let model = make { _, _ in throw URLError(.badServerResponse) }
        await model.submit()
        #expect(model.error == .server)
    }

    @Test func cancellationIsSilent() async {
        let model = make { _, _ in throw CancellationError() }
        await model.submit()
        #expect(model.error == nil)
        #expect(!model.isWorking)
    }

    @Test func isWorkingDuringSubmit() async {
        var observed: Bool?
        var modelRef: SignInViewModel?
        let model = make { _, _ in observed = modelRef?.isWorking }
        modelRef = model
        #expect(!model.isWorking)
        await model.submit()
        #expect(observed == true)
        #expect(!model.isWorking)
    }

    @Test func doubleSubmitRunsOnce() async {
        var calls = 0
        var release: CheckedContinuation<Void, Never>?
        let model = make { _, _ in
            calls += 1
            await withCheckedContinuation { release = $0 }
        }
        let first = Task { await model.submit() }
        while release == nil { await Task.yield() }
        await model.submit()
        #expect(calls == 1)
        release?.resume()
        await first.value
        #expect(calls == 1)
        #expect(!model.isWorking)
    }
}
