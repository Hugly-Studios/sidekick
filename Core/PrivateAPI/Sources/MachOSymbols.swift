import MachO

/// Looks up symbols that `dlsym` cannot see.
///
/// Some SkyLight entry points we need are file-local C++ symbols (`__ZL...`),
/// so they are absent from the dynamic symbol table but still present in the
/// image's `LC_SYMTAB`. Ported from yabai's `macho_find_symbol`.
enum MachOSymbols {
    static func localSymbol(imagePath: String, name: String) -> UnsafeRawPointer? {
        for index in 0..<_dyld_image_count() {
            guard let imageName = _dyld_get_image_name(index),
                String(cString: imageName) == imagePath,
                let header = _dyld_get_image_header(index)
            else { continue }

            return symbol(
                named: name,
                header: UnsafeRawPointer(header).assumingMemoryBound(to: mach_header_64.self),
                slide: _dyld_get_image_vmaddr_slide(index)
            )
        }

        return nil
    }

    private static func symbol(
        named name: String,
        header: UnsafePointer<mach_header_64>,
        slide: Int
    ) -> UnsafeRawPointer? {
        var cursor = UnsafeRawPointer(header).advanced(by: MemoryLayout<mach_header_64>.size)
        var linkedit: UnsafePointer<segment_command_64>?
        var symtab: UnsafePointer<symtab_command>?

        for _ in 0..<Int(header.pointee.ncmds) {
            let command = cursor.assumingMemoryBound(to: load_command.self)

            switch command.pointee.cmd {
            case UInt32(LC_SEGMENT_64):
                let segment = cursor.assumingMemoryBound(to: segment_command_64.self)
                if segmentName(segment.pointee.segname) == SEG_LINKEDIT {
                    linkedit = segment
                }
            case UInt32(LC_SYMTAB):
                symtab = cursor.assumingMemoryBound(to: symtab_command.self)
            default:
                break
            }

            cursor = cursor.advanced(by: Int(command.pointee.cmdsize))
        }

        guard let linkedit, let symtab else { return nil }

        let linkeditBase =
            UInt(linkedit.pointee.vmaddr) - UInt(linkedit.pointee.fileoff) + UInt(bitPattern: slide)

        guard
            let strings = UnsafeRawPointer(bitPattern: linkeditBase + UInt(symtab.pointee.stroff)),
            let symbols = UnsafeRawPointer(bitPattern: linkeditBase + UInt(symtab.pointee.symoff))
        else { return nil }

        for entryIndex in 0..<Int(symtab.pointee.nsyms) {
            let entry =
                symbols
                .advanced(by: entryIndex * MemoryLayout<nlist_64>.size)
                .assumingMemoryBound(to: nlist_64.self)
            let entryName =
                strings
                .advanced(by: Int(entry.pointee.n_un.n_strx))
                .assumingMemoryBound(to: CChar.self)

            guard String(cString: entryName) == name else { continue }

            return UnsafeRawPointer(
                bitPattern: UInt(entry.pointee.n_value) + UInt(bitPattern: slide)
            )
        }

        return nil
    }

    private static func segmentName(
        _ raw: (
            CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
            CChar, CChar, CChar, CChar
        )
    ) -> String {
        withUnsafeBytes(of: raw) { bytes in
            guard let base = bytes.baseAddress else { return "" }
            return String(cString: base.assumingMemoryBound(to: CChar.self))
        }
    }
}
