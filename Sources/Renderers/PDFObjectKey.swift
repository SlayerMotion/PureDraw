//
//  PDFObjectKey.swift
//  PureDraw
//

/// An object-table key: a PDF indirect object's number and generation.
struct PDFObjectKey: Hashable {
    let number: Int
    let generation: Int

    init(_ number: Int, _ generation: Int) {
        self.number = number
        self.generation = generation
    }
}
