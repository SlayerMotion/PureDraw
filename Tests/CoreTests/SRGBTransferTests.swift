//
//  SRGBTransferTests.swift
//  PureDraw
//

@testable import Core
import Foundation
import Testing

/// The sRGB transfer function is the exact IEC 61966-2-1 mapping. These check the fixed points, the
/// standard mid-gray values, continuity at the segment join, the round trip, and that the `Color`
/// conversions apply it per channel while leaving alpha untouched.
struct SRGBTransferTests {
    private func approx(_ a: Double, _ b: Double, tol: Double = 1e-9) -> Bool {
        abs(a - b) <= tol
    }

    @Test func fixedPointsAreExact() {
        #expect(SRGBTransfer.encode(0) == 0)
        #expect(approx(SRGBTransfer.encode(1), 1))
        #expect(SRGBTransfer.decode(0) == 0)
        #expect(approx(SRGBTransfer.decode(1), 1))
    }

    @Test func standardMidGrayValues() {
        // The documented sRGB values: linear 0.5 encodes to ~0.7354, encoded 0.5 decodes to ~0.2140.
        #expect(approx(SRGBTransfer.encode(0.5), 0.735_356_983_052_449_5, tol: 1e-12))
        #expect(approx(SRGBTransfer.decode(0.5), 0.214_041_140_482_232_5, tol: 1e-12))
    }

    @Test func continuousAtTheSegmentJoin() {
        // The linear segment and the power curve meet at the encode threshold without a step.
        let threshold = 0.003_130_8
        let linear = 12.92 * threshold
        let curve = 1.055 * Foundation.pow(threshold, 1.0 / 2.4) - 0.055
        #expect(approx(linear, curve, tol: 1e-5))
    }

    @Test func roundTripIsIdentity() {
        for value in stride(from: 0.0, through: 1.0, by: 0.05) {
            #expect(approx(SRGBTransfer.decode(SRGBTransfer.encode(value)), value, tol: 1e-12))
        }
    }

    @Test func monotonicAndOrdered() {
        // Decoding lowers mid-tones (gamma > 1), encoding raises them.
        #expect(SRGBTransfer.decode(0.5) < 0.5)
        #expect(SRGBTransfer.encode(0.5) > 0.5)
    }

    @Test func colorConversionsApplyPerChannelAndKeepAlpha() {
        let color = Color(red: 0.2, green: 0.5, blue: 0.8, alpha: 0.4)
        let linear = color.linearized()
        #expect(approx(linear.red, SRGBTransfer.decode(0.2)))
        #expect(approx(linear.green, SRGBTransfer.decode(0.5)))
        #expect(approx(linear.blue, SRGBTransfer.decode(0.8)))
        #expect(linear.alpha == 0.4)
        // Re-encoding returns the original color.
        let roundTrip = linear.sRGBEncoded()
        #expect(approx(roundTrip.red, 0.2, tol: 1e-9))
        #expect(approx(roundTrip.green, 0.5, tol: 1e-9))
        #expect(approx(roundTrip.blue, 0.8, tol: 1e-9))
    }
}
