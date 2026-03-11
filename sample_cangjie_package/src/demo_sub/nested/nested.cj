/**
 * Nested sub-package for testing multi-level package nesting (like deepnames).
 * Same signature as root demo() ((): Unit). Path demo_sub/nested avoids repeated segment name.
 */
package lesson_demo.demo_sub.nested

// Demo with same signature as main demo ((): Unit) but different output (George, Hamid, Ilias).
public func demo(): Unit {
    println("=== demo_sub/nested/demo: George, Hamid, Ilias ===")
    println("Students: George (3001), Hamid (3002), Ilias (3003)")
}
