import Foundation

/// 探针错误分类
public enum ProbeErrorKind: String, Codable {
    case timeout
    case dns
    case tls
    case cannotConnect
    case httpStatus
    case invalidResponse
    case cancelled
    case unknown
}

/// 单次探测样本。
/// - latency 为 nil 表示本次未拿到有效往返时长（网络层失败）。
/// - 只要收到任意 HTTP 响应即视为「服务器可达」，此时 errorKind 为 nil，
///   即使状态码为 4xx/5xx（这类信息通过 httpStatusCode 暴露，由上层解读）。
public struct ProbeSample {
    public let targetURL: URL
    public let timestamp: Date
    public let latency: TimeInterval?
    public let httpStatusCode: Int?
    public let errorKind: ProbeErrorKind?

    /// 是否成功到达服务器（拿到任意 HTTP 响应）
    public var serverReachable: Bool { httpStatusCode != nil && errorKind == nil }

    public init(targetURL: URL,
                timestamp: Date,
                latency: TimeInterval?,
                httpStatusCode: Int?,
                errorKind: ProbeErrorKind?) {
        self.targetURL = targetURL
        self.timestamp = timestamp
        self.latency = latency
        self.httpStatusCode = httpStatusCode
        self.errorKind = errorKind
    }
}

extension ProbeErrorKind {
    init?(nsError error: Error) {
        let e = error as NSError
        switch e.code {
        case NSURLErrorTimedOut:
            self = .timeout
        case NSURLErrorDNSLookupFailed, NSURLErrorCannotFindHost:
            self = .dns
        case NSURLErrorSecureConnectionFailed,
             NSURLErrorServerCertificateHasBadDate,
             NSURLErrorServerCertificateUntrusted,
             NSURLErrorServerCertificateHasUnknownRoot,
             NSURLErrorServerCertificateNotYetValid,
             NSURLErrorClientCertificateRejected,
             NSURLErrorClientCertificateRequired:
            self = .tls
        case NSURLErrorCancelled:
            self = .cancelled
        case NSURLErrorCannotConnectToHost,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorNotConnectedToInternet,
             NSURLErrorInternationalRoamingOff:
            self = .cannotConnect
        default:
            self = .unknown
        }
    }
}
