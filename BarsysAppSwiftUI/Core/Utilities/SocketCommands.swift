//
//  SocketCommands.swift
//  BarsysAppSwiftUI
//
//  Direct port of `enum SocketCommands` from
//  BarsysApp/Helpers/Constants/Constants.swift. The string values match the
//  exact protocol the Barsys backend speaks over the WebSocket connection,
//  so when SocketService is wired to a real socket implementation no
//  string literals need to be re-derived.
//

import Foundation

enum SocketCommands {
    static let controlReleaseCommand            = "CONTROL_RELEASED:"
    static let controlGrantedCommand            = "CONTROL_GRANTED:"
    static let controlDeclinedReadCommand       = "CONTROL_DECLINED"
    static let waitingAreaJoinedReadCommand     = "WAITING_AREA_JOINED"
    static let errorMachineOfflineReadCommand   = "ERROR:MACHINE_OFFLINE"
    static let machineStatusAvailableReadCommand = "MACHINE_STATUS:AVAILABLE"
    static let peerClosedReadCommand            = "PEERCLOSED"
    static let dataFlushedCommandStr            = "DATA Flushed"
    static let cancelledReadCommand             = "CANCELLED"
    static let pingCommand                      = "PING"
}

enum DateFormatConstants {
    static let shortDate              = "MM/dd/yyyy"
    static let yearMonthDay           = "yyyy-MM-dd"
    static let dateFormatForStations  = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSSSS'Z'"
    static let localeForStations      = "en_US_POSIX"
    static let localeForDateOfBirth   = "en_US"
}
