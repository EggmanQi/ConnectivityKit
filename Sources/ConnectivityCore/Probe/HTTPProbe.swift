import Foundation

/// 独立、无缓存的 HTTP 探针。不携带登录态、公共参数或签名。
final class HTTPProbe {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    /// 发起一次探测，结果在完成时通过 completion 返回（调用方负责回自己的队列）。
    func probe(_ target: ProbeTarget, completion: @escaping (ProbeSample) -> Void) {
        var request = URLRequest(url: target.url)
        request.httpMethod = target.method
        request.timeoutInterval = target.timeout
        for (key, value) in target.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let start = Date()
        let task = session.dataTask(with: request) { _, response, error in
            var latency: TimeInterval?
            var statusCode: Int?
            var errorKind: ProbeErrorKind?

            if let http = response as? HTTPURLResponse {
                // 任意 HTTP 响应都代表服务器可达。
                statusCode = http.statusCode
                if error != nil {
                    // 罕见：既有响应又有错误，按可达处理，忽略传输错误。
                }
            } else if let error = error {
                errorKind = ProbeErrorKind(nsError: error)
                if errorKind == .cancelled {
                    // 取消不算失败样本，交由引擎自行判定（通常不会回调）。
                }
            } else {
                errorKind = .invalidResponse
            }

            // 成功拿到响应的请求才有有效延迟；错误统一 latency = nil。
            if statusCode != nil {
                latency = Date().timeIntervalSince(start)
            }

            let sample = ProbeSample(targetURL: target.url,
                                     timestamp: Date(),
                                     latency: latency,
                                     httpStatusCode: statusCode,
                                     errorKind: errorKind)
            completion(sample)
        }
        task.resume()
    }
}
