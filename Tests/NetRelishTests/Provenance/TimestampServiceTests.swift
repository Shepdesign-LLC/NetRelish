import Foundation
import Pantry
import Testing
@testable import NetRelish

/// A real exchange with DigiCert's public timestamp authority, recorded 2026-11-11 with
/// `openssl ts -query -sha256 -cert` and one POST. The page it vouches for is 64 random bytes.
/// The authority's certificate ("DigiCert SHA256 RSA4096 Timestamp Responder 2026 1") runs
/// out on 2037-11-04; if these start failing around then, record a new exchange.
private enum Recorded {
    static let digest: [UInt8] = hex("74ef74aa1922780b92f856333677f1c379259ee428f544ea926357a95043a307")
    static let nonce: [UInt8] = hex("edf51aa0c75a6e50")
    static var request: TimestampRequest { TimestampRequest(digest: digest, nonce: nonce) }
    static let reply = data([
        "MIIXdDADAgEAMIIXawYJKoZIhvcNAQcCoIIXXDCCF1gCAQMxDzANBglghkgBZQMEAgEFADCBgwYLKoZIhvcNAQkQAQSgdARyMHAC",
        "AQEGCWCGSAGG/WwHATAxMA0GCWCGSAFlAwQCAQUABCB073SqGSJ4C5L4VjM2d/HDeSWe5Cj1ROqSY1epUEOjBwIRAPSta7mMLk7W",
        "yENI9UuFr+EYDzIwMjYxMTExMTIyMTA3WgIJAO31GqDHWm5QoIITOjCCBu0wggTVoAMCAQICEAhP3DNPfkVO28MPj/mSGDUwDQYJ",
        "KoZIhvcNAQELBQAwaTELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMUEwPwYDVQQDEzhEaWdpQ2VydCBUcnVz",
        "dGVkIEc0IFRpbWVTdGFtcGluZyBSU0E0MDk2IFNIQTI1NiAyMDI1IENBMTAeFw0yNjA4MDUwMDAwMDBaFw0zNzExMDQyMzU5NTla",
        "MGMxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjE7MDkGA1UEAxMyRGlnaUNlcnQgU0hBMjU2IFJTQTQwOTYg",
        "VGltZXN0YW1wIFJlc3BvbmRlciAyMDI2IDEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC2e6byyf7NSvjUm0xls/04",
        "xjD4fAkOkbnGQi7+Wpx81iYxfzViaxSIctuH3KSl5YEYpMuFgGsA31N2D9ATMbfZdw5uaAhuWevQKhDdZIB4NnqcfpfpWQXJiQnD",
        "dAElETC+bhSEvNLGbA8DtwUpFMQ4yyYQSPqomT92osQAv6hBi47ATZS6JfVWe6XxhF4jJZ3iSAuf2Cros1czRSmWRHqMv9AfGZvp",
        "8ygYElhudpQjtcPpwoOl6QrZJUyV3iINvN4cO05prGV0fkjG426xDr2d3z9lcSIHkdvGPdGUrXdxfVbgOUVcp2/8ISEzwKPW++Wa",
        "+E2ujI91EZtukGWDJ/xZ27k3oHKEXBRGfRTqjOU+jE3ba/5++JSE/7oNHnjs5mekExYN96LV/mxUbCKJb8pBNY4r3uD7hEmk/M81",
        "XhVgwDA7aMzYC3LZBg9WY5BMmbSay5ecmtJuXaB/0nKWmQmVZeqTVDgsmzHP5MQuhAJkiWNuC9MmCg9TZHXbJ2/yLVSov9p16UDT",
        "LtT0+aa1vN71fHeu1qMLlLNB3WOB/ADCxr3S/1hxI92Z6jKgEED/btwIvbfuXkNNhg8MtDg43c4tMZae9FvqMOt/9PvmAxF9TNIs",
        "IFB8G6yb36ZJZGUL8N/pL971DyLXcK6HM5PYnH5X+eVtczhCgHCVQCF6XDAlPQIDAQABo4IBlTCCAZEwDAYDVR0TAQH/BAIwADAd",
        "BgNVHQ4EFgQUFMljijAu1Er7bpTz5uNAfvXszeIwHwYDVR0jBBgwFoAU729TSunkBnx6yuKQVvYv1Ensy04wDgYDVR0PAQH/BAQD",
        "AgeAMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMIGVBggrBgEFBQcBAQSBiDCBhTAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGln",
        "aWNlcnQuY29tMF0GCCsGAQUFBzAChlFodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkRzRUaW1lU3Rh",
        "bXBpbmdSU0E0MDk2U0hBMjU2MjAyNUNBMS5jcnQwXwYDVR0fBFgwVjBUoFKgUIZOaHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0Rp",
        "Z2lDZXJ0VHJ1c3RlZEc0VGltZVN0YW1waW5nUlNBNDA5NlNIQTI1NjIwMjVDQTEuY3JsMCAGA1UdIAQZMBcwCAYGZ4EMAQQCMAsG",
        "CWCGSAGG/WwHATANBgkqhkiG9w0BAQsFAAOCAgEAjcU6YR6dUgrfmawJgH59KECxa9Ji8sEi2g10CBDaMiqsaxWyW5cwlT/6ZF5s",
        "FznazqVsoC85U9dqLOYqQwst+UQQoNlDHgKRLa3xoc+OReFreFhnTXSG0Vrd2E2CZqUfm+5a+He1MJ/h+tNLuA+0Zzhn/Fo+FDYA",
        "HWZHx4R79ZsfRFYe9UiXpXBDf6DkUo183Y38NYmR/XfDYf7YZ+oR9t3flbDwK+hgGMs0gNNp1w9Z2CyOyI5or/sSwomAuNQ0hWC9",
        "xoU4stD8aWsD7RkcmgVRs6vlIk3zPKQ+ylcheWkMlj+CoVRlFE55pv0ZWCaFt04lwP/rdGHE9qEVQZtyRE42ox7oNgC/r+Y4bSlZ",
        "3dw9K2x1xLtu6PkPKeLBFjzKigwfqm3Hm+k/+lnME8F5kPZTgiy2HLEHklpryqs6QHnPXrRNeIzkAMyylnRN8P0wmirS0WkU+ywp",
        "EWFZ4QNg+9xS43tTuW9x0eXh7NDc1P/sV+zWxHXKH8tFt1ncHdVzqrZaYPyYMLSn2TOXajveJW1L3joiQSPsWRGxkbDDW15jERFE",
        "4LvjnGu2O9zD1nLJSMdlYZEikl4w2w+q4IN/R+TIe0H4ngCI1moJCTbevGH4punIxM1Uoi0nmX3ZK+XbRT01uowE5ViXWHng0Rgs",
        "mrX/EdYUo80r3TfMlkD0/YMwgga0MIIEnKADAgECAhANx6xXBf8hmS5AQyIMOkmGMA0GCSqGSIb3DQEBCwUAMGIxCzAJBgNVBAYT",
        "AlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lDZXJ0IFRy",
        "dXN0ZWQgUm9vdCBHNDAeFw0yNTA1MDcwMDAwMDBaFw0zODAxMTQyMzU5NTlaMGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdp",
        "Q2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBD",
        "QTEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC0eDHTCphBcr48RsAcrHXbo0ZodLRRF51NrY0NlLWZloMsVO1DahGP",
        "NRcybEKq+RuwOnPhof6pvF4uGjwjqNjfEvUi6wuim5bap+0lgloM2zX4kftn5B1IpYzTqpyFQ/4Bt0mAxAHeHYNnQxqXmRinvuNg",
        "xVBdJkf77S2uPoCj7GH8BLuxBG5AvftBdsOECS1UkxBvMgEdgkFiDNYiOTx4OtiFcMSkqTtF2hfQz3zQSku2Ws3IfDReb6e3mmdg",
        "lTcaarps0wjUjsZvkgFkriK9tUKJm/s80FiocSk1VYLZlDwFt+cVFBURJg6zMUjZa/zbCclF83bRVFLeGkuAhHiGPMvSGmhgaTzV",
        "yhYn4p0+8y9oHRaQT/aofEnS5xLrfxnGpTXiUOeSLsJygoLPp66bkDX1ZlAeSpQl92QOMeRxykvq6gbylsXQskBBBnGy3tW/AMOM",
        "CZIVNSaz7BX8VtYGqLt9MmeOreGPRdtBx3yGOP+rx3rKWDEJlIqLXvJWnY0v5ydPpOjL6s36czwzsucuoKs7Yk/ehb//Wx+5kMqI",
        "MRvUBDx6z1ev+7psNOdgJMoiwOrUG2ZdSoQbU2rMkpLiQ6bGRinZbI4OLu9BMIFm1UUl9VnePs6BaaeEWvjJSjNm2qA+sdFUeEY0",
        "qVjPKOWug/G6X5uAiynM7Bu2ayBjUwIDAQABo4IBXTCCAVkwEgYDVR0TAQH/BAgwBgEB/wIBADAdBgNVHQ4EFgQU729TSunkBnx6",
        "yuKQVvYv1Ensy04wHwYDVR0jBBgwFoAU7NfjgtJxXWRM3y5nP+e6mK4cD08wDgYDVR0PAQH/BAQDAgGGMBMGA1UdJQQMMAoGCCsG",
        "AQUFBwMIMHcGCCsGAQUFBwEBBGswaTAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEEGCCsGAQUFBzAChjVo",
        "dHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0LmNydDBDBgNVHR8EPDA6MDigNqA0hjJodHRw",
        "Oi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0LmNybDAgBgNVHSAEGTAXMAgGBmeBDAEEAjALBglghkgB",
        "hv1sBwEwDQYJKoZIhvcNAQELBQADggIBABfO+xaAHP4HPRF2cTC9vgvItTSmf83Qh8WIGjB/T8ObXAZz8OjuhUxjaaFdleMM0lBr",
        "yPTQM2qEJPe36zwbSI/mS83afsl3YTj+IQhQE7jU/kXjjytJgnn0hvrV6hqWGd3rLAUt6vJy9lMDPjTLxLgXf9r5nWMQwr8Myb9r",
        "EVKChHyfpzee5kH0F8HABBgr0UdqirZ7bowe9Vj2AIMD8liyrukZ2iA/wdG2th9y1IsA0QF8dTXqvcnTmpfeQh35k5zOCPmSNq1U",
        "H410ANVko43+Cdmu4y81hjajV/gxdEkMx1NKU4uHQcKfZxAvBAKqMVuqte69M9J6A47OvgRaPs+2ykgcGV00TYr2Lr3ty9qIijan",
        "rUR3anzEwlvzZiiyfTPjLbnFRsjsYg39OlV8cipDoq7+qNNjqFzeGxcytL5TTLL4ZaoBdqbhOhZ3ZRDUphPvSRmMThi0vw9vODRz",
        "W6AxnJll38F0cuJG7uEBYTptMSbhdhGQDpOXgpIUsWTjd6xpR6oaQf/DJbg3s6KCLPAlZ66RzIg9sC+NJpud/v4+7RWsWCiKi9EO",
        "LLHfMR2ZyJ/+xhCx9yHbxtl5TPau1j/1MIDpMPx0LckTetiSuEtQvLsNz3Qbp7wGWqbIiOWCnb5WqxL3/BAPvIXKUjPSxyZsq8Wh",
        "baM2tszWkPZPubdcMIIFjTCCBHWgAwIBAgIQDpsYjvnQLefv21DiCEAYWjANBgkqhkiG9w0BAQwFADBlMQswCQYDVQQGEwJVUzEV",
        "MBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSQwIgYDVQQDExtEaWdpQ2VydCBBc3N1cmVk",
        "IElEIFJvb3QgQ0EwHhcNMjIwODAxMDAwMDAwWhcNMzExMTA5MjM1OTU5WjBiMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNl",
        "cnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSEwHwYDVQQDExhEaWdpQ2VydCBUcnVzdGVkIFJvb3QgRzQwggIiMA0G",
        "CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC/5pBzaN675F1KPDAiMGkz7MKnJS7JIT3yithZwuEppz1Yq3aaza57G4QNxDAf8xuk",
        "OBbrVsaXbR2rsnnyyhHS5F/WBTxSD1Ifxp4VpX6+n6lXFllVcq9ok3DCsrp1mWpzMpTREEQQLt+C8weE5nQ7bXHiLQwb7iDVySAd",
        "YyktzuxeTsiT+CFhmzTrBcZe7FsavOvJz82sNEBfsXpm7nfISKhmV1efVFiODCu3T6cw2Vbuyntd463JT17lNecxy9qTXtyOj4Da",
        "tpGYQJB5w3jHtrHEtWoYOAMQjdjUN6QuBX2I9YI+EJFwq1WCQTLX2wRzKm6RAXwhTNS8rhsDdV14Ztk6MUSaM0C/CNdaSaTC5qmg",
        "Z92kJ7yhTzm1EVgX9yRcRo9k98FpiHaYdj1ZXUJ2h4mXaXpI8OCiEhtmmnTK3kse5w5jrubU75KSOp493ADkRSWJtppEGSt+wJS0",
        "0mFt6zPZxd9LBADMfRyVw4/3IbKyEbe7f/LVjHAsQWCqsWMYRJUadmJ+9oCw++hkpjPRiQfhvbfmQ6QYuKZ3AeEPlAwhHbJUKSWJ",
        "bOUOUlFHdL4mrLZBdd56rF+NP8m800ERElvlEFDrMcXKchYiCd98THU/Y+whX8QgUWtvsauGi0/C1kVfnSD8oR7FwI+isX4KJpn1",
        "5GkvmB0t9dmpsh3lGwIDAQABo4IBOjCCATYwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQU7NfjgtJxXWRM3y5nP+e6mK4cD08w",
        "HwYDVR0jBBgwFoAUReuir/SSy4IxLVGLp6chnfNtyA8wDgYDVR0PAQH/BAQDAgGGMHkGCCsGAQUFBwEBBG0wazAkBggrBgEFBQcw",
        "AYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEMGCCsGAQUFBzAChjdodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNl",
        "cnRBc3N1cmVkSURSb290Q0EuY3J0MEUGA1UdHwQ+MDwwOqA4oDaGNGh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFz",
        "c3VyZWRJRFJvb3RDQS5jcmwwEQYDVR0gBAowCDAGBgRVHSAAMA0GCSqGSIb3DQEBDAUAA4IBAQBwoL9DXFXnOF+go3QbPbYW1/e/",
        "Vwe9mqyhhyzshV6pGrsi+IcaaVQi7aSId229GhT0E0p6Ly23OO/0/4C5+KH38nLeJLxSA8hO0Cre+i1Wz/n096wwepqLsl7Uz9FD",
        "RJtDIeuWcqFItJnLnU+nBgMTdydE1Od/6Fmo8L8vC6bp8jQ87PcDx4eo0kxAGTVGamlUsLihVo7spNU96LHc/RzY9HdaXFSMb++h",
        "UD38dglohJ9vytsgjTVgHAIDyyCwrFigDkBjxZgiwbJZ9VVrzyerbHbObyMt9H5xaiNrIv8SuFQtJ37YOtnwtoeW/VvRXKwYw02f",
        "c7cBqZ9Xql4o4rmUMYIDfDCCA3gCAQEwfTBpMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4xQTA/BgNVBAMT",
        "OERpZ2lDZXJ0IFRydXN0ZWQgRzQgVGltZVN0YW1waW5nIFJTQTQwOTYgU0hBMjU2IDIwMjUgQ0ExAhAIT9wzT35FTtvDD4/5khg1",
        "MA0GCWCGSAFlAwQCAQUAoIHRMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAcBgkqhkiG9w0BCQUxDxcNMjYxMTExMTIyMTA3",
        "WjArBgsqhkiG9w0BCRACDDEcMBowGDAWBBRR2avaA0lz2E9CZqykgkjms2nEOTAvBgkqhkiG9w0BCQQxIgQgxr2MteghMBmXDGM2",
        "SKWm2sOh/eU+AutNoe1ENf7QvVQwNwYLKoZIhvcNAQkQAi8xKDAmMCQwIgQgLaCdp/QTH5/nLbbF5unJZWdVrwQ/HqdCzA0hIOFB",
        "6/wwDQYJKoZIhvcNAQEBBQAEggIAX2o7raoUe3iVe7Zm7yaPYchJwb18rgxhXqKWDIxqEYjXyU+qA3kldLDlH+brZ5EvKSaiUvLo",
        "jymZYJUm0iin+Og2KzTt2enbhQsv/pX8ivBPO6ipObpYfapoVaG83E6TRr4pZEo6dbW9IJqO3rrl/ma2veBtQF1d53QUVp4pIQ7S",
        "OhMDsyfoJc56Q0gifWu53IGuXN2JmEwasfmzh7aCj1q/5g36DBRqVyOjON8jHj7bH29QKrzTu5CIfchdP3uItCyLcgZtY4WWQh0J",
        "dxHq1MKoqg4pP2By2QOaJdRYpB2GM4+eGdNVdizOlrSc0hrgnC05e8VxsHSEmcfs5LDu3fTt/4LykJuDt6Cc70t3hLMNkeQWQVb2",
        "nD44r8dcbNM1YcRkAAjvJcfNYSg8Vqu3As1yj6VIf5uEgjdq4w5P7jhmtUUhW1TDaz228LJXQOPhDMWSO4BODkGfGBGC+zWnLkbY",
        "pN0pNjKrW6nQcl4lQmLLwWm8jriTcSKp9rJyH7oRMeer8jqXOVKKp/mGJ/ut5Q9WOE1Vjh7oO5vOCiH8AtnM7s+IW2wliWpgbRQR",
        "FJcQb9HuSVFUXqY/JBplml4Tamhuci5pLgLguMAS+TTIn/ZsVXoFQQeen2yz/GNmOlTQFKYgKx2LjCJndHq8IyE73PuDVY+CxUPg",
        "nG2H4zaw7A4=",
    ])

    /// The same shape of reply from a throwaway authority made with openssl (the one
    /// Tests/PantryTests uses): properly formed, properly signed, and trusted by nobody.
    static let strangerDigest: [UInt8] = hex("a1b3e0f8033c68a27e5cd17a108a0888b870c29f5cd2f6dfc51417a9ed0892e5")
    static let strangerNonce: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
    static var strangerRequest: TimestampRequest { TimestampRequest(digest: strangerDigest, nonce: strangerNonce) }
    static let strangerReply = data([
        "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",
    ])

    static func data(_ lines: [String]) -> Data { Data(base64Encoded: lines.joined())! }
    static func hex(_ text: String) -> [UInt8] {
        stride(from: 0, to: text.count, by: 2).map { i in
            let start = text.index(text.startIndex, offsetBy: i)
            return UInt8(text[start..<text.index(start, offsetBy: 2)], radix: 16)!
        }
    }
}

/// Answers for the authority, so no test reaches the network. One answer per host name, so
/// tests running side by side don't see each other's.
final class StandInAuthority: URLProtocol, @unchecked Sendable {
    enum Answer {
        case reply(status: Int = 200, headers: [String: String] = [:], body: Data)
        case redirect(to: URL)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var answers: [String: Answer] = [:]
    nonisolated(unsafe) private static var asked: [String: Int] = [:]

    static func answer(_ host: String, with answer: Answer) { lock.withLock { answers[host] = answer } }
    static func timesAsked(_ host: String) -> Int { lock.withLock { asked[host] ?? 0 } }

    /// A service that asks `host`, and is answered here.
    static func service(_ host: String) throws -> TimestampService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StandInAuthority.self]
        return try #require(TimestampService(address: "http://\(host)/", session: URLSession(configuration: configuration)))
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url, let host = url.host else { return }
        let answer = Self.lock.withLock { () -> Answer? in
            Self.asked[host, default: 0] += 1
            return Self.answers[host]
        }
        switch answer {
        case .reply(let status, let headers, let body):
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .redirect(let target):
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1",
                                           headerFields: ["Location": target.absoluteString])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
            client?.urlProtocolDidFinishLoading(self)
        case nil:
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
        }
    }
}

@Suite("Timestamp service") struct TimestampServiceTests {

    // MARK: Who signed it

    @Test("A real timestamp from DigiCert checks out")
    func realTimestampIsValid() throws {
        let stamp = try Timestamp(response: Recorded.reply, for: Recorded.request)
        #expect(TimestampService.signatureIsValid(stamp.token))
    }

    @Test("Change one bit of what the authority signed, and it no longer checks out")
    func alteredTimestampIsRefused() throws {
        let stamp = try Timestamp(response: Recorded.reply, for: Recorded.request)
        // The last byte of the signed content is the end of the nonce.
        let signed = try Timestamp.signedContent(in: stamp.token)
        let range = try #require(stamp.token.range(of: signed))
        var altered = stamp.token
        altered[range.upperBound - 1] ^= 0x01
        #expect(try Timestamp.signedContent(in: altered) != signed)
        #expect(!TimestampService.signatureIsValid(altered))
    }

    @Test("A well-formed, properly signed timestamp from an authority this Mac doesn't trust is refused")
    func strangersTimestampIsRefused() throws {
        let stamp = try Timestamp(response: Recorded.strangerReply, for: Recorded.strangerRequest)
        #expect(!TimestampService.signatureIsValid(stamp.token))
    }

    @Test("Bytes that aren't a token at all are refused")
    func noiseIsRefused() {
        #expect(!TimestampService.signatureIsValid(Data()))
        #expect(!TimestampService.signatureIsValid(Data("not a token".utf8)))
        #expect(!TimestampService.signatureIsValid(Data(repeating: 0x30, count: 4_096)))
    }

    // MARK: Which address it will ask

    @Test("Only a plain web address is an authority",
          arguments: ["", "timestamp.digicert.com", "file:///etc/hosts", "javascript:alert(1)", "ftp://timestamp.digicert.com",
                      "https://", "https://someone:secret@timestamp.digicert.com/", "data:text/plain,hello"])
    func refusesAddressesThatAreNotWebAddresses(address: String) {
        #expect(TimestampService(address: address) == nil)
    }

    @Test("DigiCert's address, and an https one, are accepted")
    func acceptsWebAddresses() throws {
        #expect(try #require(TimestampService(address: "http://timestamp.digicert.com")).name == "timestamp.digicert.com")
        #expect(TimestampService(address: "https://timestamp.example.com/tsa") != nil)
    }

    // MARK: What it does with the reply

    @Test("A real reply for this request is kept, exactly as it arrived")
    func keepsARealReply() async throws {
        StandInAuthority.answer("real.test", with: .reply(headers: ["Content-Type": "application/timestamp-reply"], body: Recorded.reply))
        let reply = try await StandInAuthority.service("real.test").timestamp(Recorded.request)
        #expect(reply == Recorded.reply)
    }

    @Test("A redirect is not followed: the fingerprint goes to the authority that was asked, and nowhere else")
    func doesNotFollowRedirects() async throws {
        StandInAuthority.answer("moved.test", with: .redirect(to: URL(string: "http://elsewhere.test/collect")!))
        StandInAuthority.answer("elsewhere.test", with: .reply(body: Recorded.reply))
        let service = try StandInAuthority.service("moved.test")
        await #expect(throws: TimestampUnreachable.self) { try await service.timestamp(Recorded.request) }
        #expect(StandInAuthority.timesAsked("moved.test") == 1)
        #expect(StandInAuthority.timesAsked("elsewhere.test") == 0)
    }

    @Test("A reply longer than a timestamp is given up on, whether or not it says how long it is")
    func givesUpOnLongReplies() async throws {
        let long = Data(repeating: 0x30, count: TimestampService.replyLimit + 1)
        StandInAuthority.answer("long.test", with: .reply(body: long))
        StandInAuthority.answer("long-and-says-so.test", with: .reply(headers: ["Content-Length": "\(long.count)"], body: long))
        for host in ["long.test", "long-and-says-so.test"] {
            let service = try StandInAuthority.service(host)
            await #expect(throws: TimestampUnreachable.self) { try await service.timestamp(Recorded.request) }
        }
    }

    @Test("Nothing that arrives can be held against the page: every bad reply is the same as no reply",
          arguments: ["refusal", "another page's timestamp", "a stranger's timestamp", "noise", "a server error", "a sign-in page"])
    func badRepliesOnlyWait(kind: String) async throws {
        let host = kind.replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "'", with: "") + ".test"
        var request = Recorded.request
        switch kind {
        case "refusal":   // TimeStampResp { PKIStatusInfo { status 2: rejection } }
            StandInAuthority.answer(host, with: .reply(body: Data([0x30, 0x05, 0x30, 0x03, 0x02, 0x01, 0x02])))
        case "another page's timestamp":   // real and signed, but for a different fingerprint
            request = TimestampRequest(digest: [UInt8](repeating: 7, count: 32), nonce: Recorded.nonce)
            StandInAuthority.answer(host, with: .reply(body: Recorded.reply))
        case "a stranger's timestamp":     // answers this request, signed by nobody this Mac trusts
            request = Recorded.strangerRequest
            StandInAuthority.answer(host, with: .reply(body: Recorded.strangerReply))
        case "noise":
            StandInAuthority.answer(host, with: .reply(body: Data("<html>hello</html>".utf8)))
        case "a server error":
            StandInAuthority.answer(host, with: .reply(status: 503, body: Data()))
        default:   // a Wi-Fi sign-in page answering for everyone
            StandInAuthority.answer(host, with: .reply(status: 200, headers: ["Content-Type": "text/html"], body: Data("<html>Sign in</html>".utf8)))
        }
        let service = try StandInAuthority.service(host)
        await #expect(throws: TimestampUnreachable.self) { try await service.timestamp(request) }
    }
}
