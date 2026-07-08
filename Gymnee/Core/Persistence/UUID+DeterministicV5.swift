import Foundation
import CryptoKit

extension UUID {
    /// RFC 4122 準拠の UUID version 5（SHA-1 / namespace + name）。
    /// 同じ namespace・name なら常に同一 UUID を返す（決定的）。
    /// Postgres の `uuid_generate_v5(namespace, name)`（uuid-ossp）と同一値になる。
    /// プリセット種目のように「全端末・サーバで同じ id に収束させたい」対象の id 採番に使う。
    init(v5Name name: String, namespace: UUID) {
        var data = Data()
        withUnsafeBytes(of: namespace.uuid) { data.append(contentsOf: $0) }   // namespace の16バイト
        data.append(contentsOf: Array(name.utf8))
        var bytes = Array(Insecure.SHA1.hash(data: data))   // 20バイト
        bytes[6] = (bytes[6] & 0x0F) | 0x50   // version 5
        bytes[8] = (bytes[8] & 0x3F) | 0x80   // variant（RFC 4122）
        self = UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
