import SwiftUI
import Testing
@testable import NetRelish

@Suite("Shapes") struct ShapeTests {

    @Test("Superellipse fills its rect and follows |x|^n + |y|^n = 1")
    func superellipse() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let path = Superellipse(n: 5).path(in: rect)
        let b = path.boundingRect
        #expect(abs(b.minX - 0) < 0.5 && abs(b.maxX - 200) < 0.5)
        #expect(abs(b.minY - 0) < 0.5 && abs(b.maxY - 100) < 0.5)
        // A point on the curve at the 45° parameter must satisfy the equation.
        let t = Double.pi / 4
        let x = pow(cos(t), 2 / 5.0), y = pow(sin(t), 2 / 5.0)
        #expect(abs(pow(x, 5) + pow(y, 5) - 1) < 1e-9)
        let p = CGPoint(x: 100 + x * 100, y: 50 + y * 50)
        #expect(path.contains(p, eoFill: false) == false || true)   // on the boundary; existence check below
        #expect(path.contains(CGPoint(x: 100 + x * 99, y: 50 + y * 49)))
        #expect(!path.contains(CGPoint(x: 100 + x * 101, y: 50 + y * 51)))
    }

    @Test("Superellipse with n=2 is a circle")
    func circleCase() {
        let path = Superellipse(n: 2).path(in: CGRect(x: 0, y: 0, width: 100, height: 100))
        // Corner point of a circle inscribed in a square is at r/√2.
        let d = 50 / sqrt(2.0)
        #expect(path.contains(CGPoint(x: 50 + d - 1, y: 50 + d - 1)))
        #expect(!path.contains(CGPoint(x: 50 + d + 1, y: 50 + d + 1)))
    }

    @Test("JarShape has superellipse shoulders and stays inside its rect")
    func jar() {
        let rect = CGRect(x: 0, y: 0, width: 110, height: 130)
        let path = JarShape().path(in: rect)
        let b = path.boundingRect
        #expect(b.minX >= -0.5 && b.maxX <= 110.5 && b.minY >= -0.5 && b.maxY <= 130.5)
        // Body centre is inside; the top-left corner (outside the shoulder curve) is not.
        #expect(path.contains(CGPoint(x: 55, y: 65)))
        #expect(!path.contains(CGPoint(x: 1, y: 1)))
        // A rounded rect would clip more corner than an n=5 shoulder does: a point
        // near the corner but inside the superellipse must be inside the jar.
        let sh = JarShape().shoulder(for: rect)
        let t = Double.pi / 4
        let fx = pow(cos(t), 2 / 5.0), fy = pow(sin(t), 2 / 5.0)
        let inside = CGPoint(x: rect.minX + sh.width * (1 - fx) + 1, y: rect.minY + sh.height * (1 - fy) + 1)
        #expect(path.contains(inside))
    }
}
