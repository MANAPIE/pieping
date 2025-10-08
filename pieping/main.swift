//
//  main.swift
//  pieping
//
//  Created by MANAPIE on 10/6/25.
//

import Cocoa

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)