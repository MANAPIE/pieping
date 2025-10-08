//
//  AppDelegate.swift
//  pieping
//
//  Created by MANAPIE on 10/6/25.
//

import Cocoa
import Foundation
import UniformTypeIdentifiers

// 요청 설정을 위한 구조체
struct RequestConfig: Codable {
    let id: UUID
    let name: String
    let url: String
    let intervalSeconds: TimeInterval
    let method: String
    let body: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, url, intervalSeconds, method, body
    }
    
    init(id: UUID = UUID(), name: String, url: String, intervalSeconds: TimeInterval, method: String = "GET", body: String? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.intervalSeconds = intervalSeconds
        self.method = method
        self.body = body
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let decodedId = try? container.decode(UUID.self, forKey: .id) {
            id = decodedId
        } else {
            id = UUID()
        }
        name = try container.decode(String.self, forKey: .name)
        url = try container.decode(String.self, forKey: .url)
        intervalSeconds = try container.decode(TimeInterval.self, forKey: .intervalSeconds)
        method = (try? container.decode(String.self, forKey: .method)) ?? "GET"
        body = try? container.decodeIfPresent(String.self, forKey: .body)
    }
}

struct RequestConfigData: Codable {
    let id: UUID
    let name: String
    let url: String
    let intervalSeconds: TimeInterval
    let method: String
    let body: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, url, intervalSeconds, method, body
    }
    
    init(id: UUID = UUID(), name: String, url: String, intervalSeconds: TimeInterval, method: String = "GET", body: String? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.intervalSeconds = intervalSeconds
        self.method = method
        self.body = body
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let decodedId = try? container.decode(UUID.self, forKey: .id) {
            id = decodedId
        } else {
            id = UUID()
        }
        name = try container.decode(String.self, forKey: .name)
        url = try container.decode(String.self, forKey: .url)
        intervalSeconds = try container.decode(TimeInterval.self, forKey: .intervalSeconds)
        method = (try? container.decode(String.self, forKey: .method)) ?? "GET"
        body = try? container.decodeIfPresent(String.self, forKey: .body)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var timers: [UUID: Timer] = [:] // 타이머 - 키를 id로 변경
    var pausedTimers: [UUID: Bool] = [:] // 타이머 일시정지 - 키를 id로 변경
    var requestConfigs: [RequestConfig] = []
    
    var menuUpdateTimer: Timer?
    
    struct UrlCheckResult {
        var success: Bool?
        var statusCode: Int?
        var responseTime: TimeInterval?
        var error: String?
        var lastCalled: Date?
    }
    var results: [UUID: UrlCheckResult] = [:] // 타이머 결과값 - 키를 id로 변경
    
    class IgnoreSSLDelegate: NSObject, URLSessionDelegate {
        func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
               let serverTrust = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        }
    }
    
    let ignoreSSLDelegate = IgnoreSSLDelegate()
    
    override init() {
        super.init()
        loadConfigurations()
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 앱이 종료되지 않도록 설정
        NSApp.setActivationPolicy(.accessory)
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.title = "⏲"
            button.toolTip = "pieping"
        }
        
        addDebugLog("[시작] pieping이 시작되었습니다.")
        addDebugLog("[정보] 설정된 타이머 개수: \(requestConfigs.count)개")
        
        setupMenu()
        
        if !requestConfigs.isEmpty {
            addDebugLog("[타이머] 모든 URL 타이머를 시작합니다.")
            startAllTimers()
        } else {
            addDebugLog("[경고] 설정된 타이머가 없습니다. 새 URL을 추가해주세요.")
        }
    }
    
    func setupMenu() {
        let menu = NSMenu()
        
        // 설정 메뉴
        let addItem = NSMenuItem(title: "새 URL 추가", action: #selector(menuItemClicked(_:)), keyEquivalent: "n")
        addItem.target = self
        addItem.tag = -10
        menu.addItem(addItem)
        
        if !requestConfigs.isEmpty {
            let editItem = NSMenuItem(title: "URL 편집", action: #selector(menuItemClicked(_:)), keyEquivalent: "e")
            editItem.target = self
            editItem.tag = -11
            menu.addItem(editItem)
            
            let deleteItem = NSMenuItem(title: "URL 삭제", action: #selector(menuItemClicked(_:)), keyEquivalent: "d")
            deleteItem.target = self
            deleteItem.tag = -12
            menu.addItem(deleteItem)
        }
        
        if !requestConfigs.isEmpty {
            menu.addItem(NSMenuItem.separator())
            // 각 URL별 수동 호출
            for (index, config) in requestConfigs.enumerated() {
                let menuItem = NSMenuItem(title: "\(config.name) [\(config.method) 실행]", action: #selector(menuItemClicked(_:)), keyEquivalent: "")
                menuItem.target = self
                menuItem.tag = index
                menu.addItem(menuItem)
            }
            
            // 모든 URL 한번에 호출
            let allRequestsItem = NSMenuItem(title: "모든 URL 호출", action: #selector(menuItemClicked(_:)), keyEquivalent: "r")
            allRequestsItem.target = self
            allRequestsItem.tag = -1 // 특별한 태그로 구분
            menu.addItem(allRequestsItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // 각 타이머별 상세 상태 표시
        for (index, config) in requestConfigs.enumerated() {
            let intervalText = config.intervalSeconds < 60 ?
                "\(Int(config.intervalSeconds))초" :
                "\(Int(config.intervalSeconds/60))분"
            let result = results[config.id]
            
            var statusText: String
            if let paused = pausedTimers[config.id], paused {
                statusText = "⏸"
            } else if let success = result?.success {
                statusText = success ? "✅" : "❌"
            } else {
                statusText = "⏳"
            }
            
            var detailText = " ("
            if let statusCode = result?.statusCode, let responseTime = result?.responseTime {
                let responseTimeMs = String(format: "%.0f", responseTime * 1000)
                detailText += "HTTP \(statusCode), \(responseTimeMs)ms"
            }
            if let lastDate = result?.lastCalled {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm:ss"
                detailText += ", " + formatter.string(from: lastDate)
            }
            detailText += ")"
            
            let menuItem = NSMenuItem(title: "\(statusText) \(config.name) [\(config.method)]: \(intervalText)마다\(detailText)", action: #selector(menuItemClicked(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.tag = 1000 + index // 태그 1000번대는 상태 표시 클릭용으로 구분
            menu.addItem(menuItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "종료", action: #selector(menuItemClicked(_:)), keyEquivalent: "q")
        quitItem.target = self
        quitItem.tag = -2 // 종료를 위한 특별한 태그
        menu.addItem(quitItem)
        
        statusItem.menu = menu
        menu.delegate = self
    }
    
    @objc func menuItemClicked(_ sender: NSMenuItem) {
        switch sender.tag {
        case -12: // URL 삭제
            showDeleteDialog()
        case -11: // URL 편집
            showEditDialog()
        case -10: // 새 URL 추가
            showAddDialog()
        case -2: // 종료
            quitApp()
        case -1: // 모든 URL 호출
            addDebugLog("[수동] 모든 URL 호출을 요청했습니다.")
            sendAllRequests()
        case 0..<requestConfigs.count: // 개별 URL 호출
            let config = requestConfigs[sender.tag]
            addDebugLog("[수동] [\(config.name)] URL 호출을 요청했습니다.")
            sendRequest(config: config)
        case 1000..<1100: // 상태 표시줄 클릭 시: 일시정지 / 재개 토글
            let idx = sender.tag - 1000
            guard idx >= 0 && idx < requestConfigs.count else { return }
            let config = requestConfigs[idx]
            let id = config.id
            
            let currentlyPaused = pausedTimers[id] ?? false
            let newPausedState = !currentlyPaused
            
            pausedTimers[id] = newPausedState
            
            if newPausedState {
                // 일시정지: 타이머 중단
                if let timer = timers[id] {
                    timer.invalidate()
                    timers.removeValue(forKey: id)
                }
                addDebugLog("[일시정지] [\(config.name)] 타이머가 일시정지 되었습니다.")
            } else {
                // 재개: 타이머 재생성
                startTimer(for: config)
                addDebugLog("[재개] [\(config.name)] 타이머가 재개되었습니다.")
            }
            
            setupMenu()
            updateMainIcon()
        default:
            break
        }
    }
    
    func startAllTimers() {
        addDebugLog("[타이머] 모든 URL 즉시 호출을 시작합니다.")
        
        // 모든 URL에 대해 즉시 한 번 호출 (일시정지 여부 상관없이 호출)
        for config in requestConfigs {
            sendRequest(config: config)
        }
        
        // 각 URL별로 타이머 설정
        for config in requestConfigs {
            if pausedTimers[config.id] == true {
                // 일시정지인 경우 타이머 생성 안함
                addDebugLog("[타이머] [\(config.name)] 타이머는 현재 일시정지 상태입니다.")
                continue
            }
            startTimer(for: config)
            
            let intervalText = config.intervalSeconds < 60 ?
                "\(Int(config.intervalSeconds))초" :
                "\(Int(config.intervalSeconds/60))분"
            addDebugLog("[타이머] [\(config.name)] 타이머 설정됨 (주기: \(intervalText))")
        }
        
        addDebugLog("[완료] 모든 타이머가 설정되었습니다.")
    }
    
    // 타이머 개별 시작 함수
    func startTimer(for config: RequestConfig) {
        // 기존 타이머 있으면 무효화 후 제거
        if let existingTimer = timers[config.id] {
            existingTimer.invalidate()
            timers.removeValue(forKey: config.id)
        }
        
        // 타이머 생성
        let timer = Timer.scheduledTimer(withTimeInterval: config.intervalSeconds, repeats: true) { [weak self] _ in
            // 일시정지 상태면 호출하지 않음
            if let paused = self?.pausedTimers[config.id], paused {
                return
            }
            self?.sendRequest(config: config)
        }
        timers[config.id] = timer
    }
    
    func sendRequest(config: RequestConfig) {
        if var result = results[config.id] {
            result.lastCalled = Date()
            results[config.id] = result
        } else {
            results[config.id] = UrlCheckResult(success: nil, statusCode: nil, responseTime: nil, error: nil, lastCalled: Date())
        }
        
        guard let url = URL(string: config.url) else {
            addDebugLog("❌[\(config.name)] 유효하지 않은 URL: \(config.url)")
            updateResult(for: config.id, success: false, statusCode: 0, responseTime: 0, error: "유효하지 않은 URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = config.method
        
        if config.method.uppercased() == "POST" {
            if let bodyString = config.body, !bodyString.isEmpty {
                request.httpBody = bodyString.data(using: .utf8)
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            } else {
                request.httpBody = nil
            }
        } else {
            request.httpBody = nil
        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        addDebugLog("[\(config.name)] 요청 시작: \(config.url) [\(config.method)]")
        
        let session = URLSession(configuration: .default, delegate: ignoreSSLDelegate, delegateQueue: nil)
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            let responseTime = CFAbsoluteTimeGetCurrent() - startTime
            
            DispatchQueue.main.async {
                if let error = error {
                    let errorMessage = error.localizedDescription
                    self?.addDebugLog("❌[\(config.name)] 에러: \(errorMessage) (응답시간: \(String(format: "%.0f", responseTime * 1000))ms)")
                    self?.updateResult(for: config.id, success: false, statusCode: 0, responseTime: responseTime, error: errorMessage)
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    let success = (200...299).contains(httpResponse.statusCode)
                    let statusEmoji = success ? "✅" : "❌"
                    let dataSize = data?.count ?? 0
                    
                    self?.addDebugLog("\(statusEmoji) [\(config.name)] HTTP \(httpResponse.statusCode) (응답시간: \(String(format: "%.0f", responseTime * 1000))ms, 크기: \(dataSize) bytes)")
                    
                    // 응답 헤더 정보도 로깅
                    if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") {
                        self?.addDebugLog("[\(config.name)] Content-Type: \(contentType)")
                    }
                    
                    self?.updateResult(for: config.id, success: success, statusCode: httpResponse.statusCode, responseTime: responseTime, error: success ? nil : "HTTP \(httpResponse.statusCode)")
                } else {
                    self?.addDebugLog("❌[\(config.name)] 알 수 없는 응답 타입")
                    self?.updateResult(for: config.id, success: false, statusCode: 0, responseTime: responseTime, error: "알 수 없는 응답 타입")
                }
            }
        }
        task.resume()
    }
    
    func sendAllRequests() {
        for config in requestConfigs {
            sendRequest(config: config)
        }
    }
    
    func updateResult(for id: UUID, success: Bool, statusCode: Int = 0, responseTime: TimeInterval = 0, error: String? = nil) {
        var result = results[id] ?? UrlCheckResult()
        result.success = success
        result.statusCode = statusCode
        result.responseTime = responseTime
        result.error = error
        results[id] = result
        setupMenu()
        updateMainIcon()
    }
    
    func updateMainIcon() {
        let allSuccess = results.values.compactMap { $0.success }.allSatisfy { $0 }
        let anyFailure = results.values.compactMap { $0.success }.contains { !$0 }
        
        if let button = statusItem.button {
            if results.isEmpty {
                button.title = "⏲"
            } else if allSuccess {
                button.title = "⏲"
            } else if anyFailure {
                button.title = "❌"
            } else {
                button.title = "⏲"
            }
        }
        
        // 2초 후 원래 아이콘으로 복구
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            if let button = self?.statusItem.button {
                button.title = "⏲"
            }
        }
    }
    
    func quitApp() {
        // 모든 타이머 정리
        timers.forEach { $0.value.invalidate() }
        timers.removeAll()
        NSApplication.shared.terminate(nil)
    }
    
    // MARK: - 설정 관리
    func loadConfigurations() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "RequestConfigs"),
           let configs = try? JSONDecoder().decode([RequestConfigData].self, from: data) {
            requestConfigs = configs.map {
                RequestConfig(id: $0.id, name: $0.name, url: $0.url, intervalSeconds: $0.intervalSeconds, method: $0.method, body: $0.body)
            }
        } else {
            // 빈 설정으로 시작
            requestConfigs = []
        }
        
        // 초기 pausedTimers 상태 초기화 (모두 재개 상태)
        pausedTimers.removeAll()
    }
    
    func saveConfigurations() {
        let defaults = UserDefaults.standard
        let configsData = requestConfigs.map {
            RequestConfigData(id: $0.id, name: $0.name, url: $0.url, intervalSeconds: $0.intervalSeconds, method: $0.method, body: $0.body)
        }
        if let data = try? JSONEncoder().encode(configsData) {
            defaults.set(data, forKey: "RequestConfigs")
        }
    }
    
    func restartAllTimers() {
        // 기존 타이머 정리
        timers.forEach { $0.value.invalidate() }
        timers.removeAll()
        results.removeAll()
        
        // pausedTimers 초기화: 재시작 시 모두 재개 상태로 변경
        pausedTimers.removeAll()
        
        // 새 타이머 시작
        startAllTimers()
        
        // 메뉴 업데이트
        setupMenu()
    }
    
    // MARK: - 디버그 기능
    func addDebugLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        
        let logEntry = "[\(timestamp)] \(message)"
        // 콘솔에 출력
        print(logEntry)
    }
    
    func showAddDialog() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "새 URL 추가"
        window.center()
        window.isReleasedWhenClosed = false
        
        let contentView = NSView()
        window.contentView = contentView
        
        let titleLabel = NSTextField(labelWithString: "정기적으로 호출할 URL 정보를 입력하세요.")
        titleLabel.font = NSFont.systemFont(ofSize: 13)
        titleLabel.textColor = .secondaryLabelColor
        
        let nameLabel = NSTextField(labelWithString: "이름:")
        let nameField = NSTextField()
        nameField.placeholderString = "예: API 서버"
        
        let urlLabel = NSTextField(labelWithString: "URL:")
        let urlField = NSTextField()
        urlField.placeholderString = "예: https://example.com/api"
        
        let methodLabel = NSTextField(labelWithString: "HTTP 메서드:")
        let methodPopup = NSPopUpButton()
        methodPopup.addItems(withTitles: ["GET", "POST"])
        methodPopup.selectItem(withTitle: "GET")
        
        let bodyLabel = NSTextField(labelWithString: "요청 본문 (POST 시):")
        let bodyField = NSTextView()
        bodyField.font = NSFont.systemFont(ofSize: 12)
        bodyField.isVerticallyResizable = true
        bodyField.isHorizontallyResizable = false
        bodyField.autoresizingMask = [.width]
        bodyField.textContainerInset = NSSize(width: 5, height: 5)
        bodyField.isEditable = false
        
        let scrollView = NSScrollView()
        scrollView.documentView = bodyField
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        
        let intervalLabel = NSTextField(labelWithString: "주기 (초):")
        let intervalField = NSTextField()
        intervalField.placeholderString = "예: 60"
        
        let addButton = NSButton(title: "추가", target: nil, action: nil)
        let cancelButton = NSButton(title: "취소", target: nil, action: nil)
        
        addButton.bezelStyle = .rounded
        cancelButton.bezelStyle = .rounded
        
        [titleLabel, nameLabel, nameField, urlLabel, urlField, methodLabel, methodPopup, bodyLabel, scrollView, intervalLabel, intervalField, addButton, cancelButton].forEach {
            contentView.addSubview($0)
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        
        NSLayoutConstraint.activate([
            // 제목 레이블
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            // 이름 레이블
            nameLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            // 이름 필드
            nameField.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 5),
            nameField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            nameField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            nameField.heightAnchor.constraint(equalToConstant: 22),
            
            // URL 레이블
            urlLabel.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 15),
            urlLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            urlLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            // URL 필드
            urlField.topAnchor.constraint(equalTo: urlLabel.bottomAnchor, constant: 5),
            urlField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            urlField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            urlField.heightAnchor.constraint(equalToConstant: 22),
            
            // HTTP 메서드 레이블
            methodLabel.topAnchor.constraint(equalTo: urlField.bottomAnchor, constant: 15),
            methodLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            methodLabel.widthAnchor.constraint(equalToConstant: 90),
            
            // HTTP 메서드 팝업
            methodPopup.centerYAnchor.constraint(equalTo: methodLabel.centerYAnchor),
            methodPopup.leadingAnchor.constraint(equalTo: methodLabel.trailingAnchor, constant: 10),
            methodPopup.widthAnchor.constraint(equalToConstant: 100),
            
            // Body 레이블
            bodyLabel.topAnchor.constraint(equalTo: methodLabel.bottomAnchor, constant: 15),
            bodyLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            bodyLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            // Body 텍스트뷰 스크롤뷰
            scrollView.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: 5),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            scrollView.heightAnchor.constraint(equalToConstant: 80),
            
            // 주기 레이블
            intervalLabel.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 15),
            intervalLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            intervalLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            // 주기 필드
            intervalField.topAnchor.constraint(equalTo: intervalLabel.bottomAnchor, constant: 5),
            intervalField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            intervalField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            intervalField.heightAnchor.constraint(equalToConstant: 22),
            
            // 버튼들 - 주기 필드 아래 충분한 공간 확보
            cancelButton.topAnchor.constraint(equalTo: intervalField.bottomAnchor, constant: 25),
            cancelButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            cancelButton.widthAnchor.constraint(equalToConstant: 80),
            cancelButton.heightAnchor.constraint(equalToConstant: 32),
            
            addButton.topAnchor.constraint(equalTo: intervalField.bottomAnchor, constant: 25),
            addButton.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -10),
            addButton.widthAnchor.constraint(equalToConstant: 80),
            addButton.heightAnchor.constraint(equalToConstant: 32)
        ])
        
        // Enable/disable bodyField editing depending on method selection
        func updateBodyFieldEnabled() {
            if methodPopup.selectedItem?.title.uppercased() == "POST" {
                bodyField.isEditable = true
                bodyField.backgroundColor = NSColor.textBackgroundColor
            } else {
                bodyField.isEditable = false
                bodyField.backgroundColor = NSColor.windowBackgroundColor
                bodyField.string = ""
            }
        }
        
        updateBodyFieldEnabled()
        
        class MethodPopupTarget: NSObject {
            let updateBodyFieldEnabled: () -> Void
            init(_ updateFunc: @escaping () -> Void) {
                self.updateBodyFieldEnabled = updateFunc
            }
            @objc func methodChanged(_ sender: NSPopUpButton) {
                updateBodyFieldEnabled()
            }
        }
        
        let methodPopupTarget = MethodPopupTarget(updateBodyFieldEnabled)
        methodPopup.target = methodPopupTarget
        methodPopup.action = #selector(MethodPopupTarget.methodChanged(_:))
        
        // Hold reference
        objc_setAssociatedObject(window, "methodPopupTarget", methodPopupTarget, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        
        var modalResponse: NSApplication.ModalResponse = .cancel
        
        let addAction = {
            let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let url = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let method = methodPopup.selectedItem?.title.uppercased() ?? "GET"
            let body = method == "POST" ? bodyField.string.trimmingCharacters(in: .whitespacesAndNewlines) : nil
            let intervalText = intervalField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard !name.isEmpty, !url.isEmpty, let interval = Double(intervalText), interval > 0 else {
                self.showErrorAlert("유효하지 않은 입력입니다. 모든 필드를 올바르게 입력해주세요.")
                return
            }
            
            let newConfig = RequestConfig(id: UUID(), name: name, url: url, intervalSeconds: interval, method: method, body: body)
            self.requestConfigs.append(newConfig)
            self.saveConfigurations()
            self.restartAllTimers()
            
            modalResponse = .OK
            NSApp.stopModal()
        }
        
        let cancelAction = {
            modalResponse = .cancel
            NSApp.stopModal()
        }
        
        // 버튼 액션 설정을 위한 임시 클래스
        class ButtonTarget: NSObject {
            let action: () -> Void
            
            init(action: @escaping () -> Void) {
                self.action = action
            }
            
            @objc func performAction() {
                action()
            }
        }
        
        let addTarget = ButtonTarget(action: addAction)
        let cancelTarget = ButtonTarget(action: cancelAction)
        
        addButton.target = addTarget
        addButton.action = #selector(ButtonTarget.performAction)
        
        cancelButton.target = cancelTarget
        cancelButton.action = #selector(ButtonTarget.performAction)
        
        objc_setAssociatedObject(window, "addTarget", addTarget, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        objc_setAssociatedObject(window, "cancelTarget", cancelTarget, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        
        window.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: window)
        
        window.close()
    }
    
    func showEditDialog() {
        guard !requestConfigs.isEmpty else { return }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 150),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "URL 편집"
        window.center()
        window.isReleasedWhenClosed = false
        
        let contentView = NSView()
        window.contentView = contentView
        
        // UI 요소들 생성
        let titleLabel = NSTextField(labelWithString: "편집할 항목을 선택하세요.")
        titleLabel.font = NSFont.systemFont(ofSize: 13)
        titleLabel.textColor = .secondaryLabelColor
        
        let selectLabel = NSTextField(labelWithString: "선택:")
        let popup = NSPopUpButton()
        
        for config in requestConfigs {
            popup.addItem(withTitle: "\(config.name) [\(config.method)] - \(config.url)")
        }
        
        let editButton = NSButton(title: "편집", target: nil, action: nil)
        let cancelButton = NSButton(title: "취소", target: nil, action: nil)
        
        editButton.bezelStyle = .rounded
        cancelButton.bezelStyle = .rounded
        
        [titleLabel, selectLabel, popup, editButton, cancelButton].forEach {
            contentView.addSubview($0)
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        
        NSLayoutConstraint.activate([
            // 제목 레이블
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            // 선택 레이블
            selectLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            selectLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            selectLabel.widthAnchor.constraint(equalToConstant: 40),
            
            // 드롭다운
            popup.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 18),
            popup.leadingAnchor.constraint(equalTo: selectLabel.trailingAnchor, constant: 10),
            popup.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            popup.heightAnchor.constraint(equalToConstant: 26),
            
            // 버튼들
            cancelButton.topAnchor.constraint(equalTo: popup.bottomAnchor, constant: 25),
            cancelButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            cancelButton.widthAnchor.constraint(equalToConstant: 80),
            cancelButton.heightAnchor.constraint(equalToConstant: 32),
            
            editButton.topAnchor.constraint(equalTo: popup.bottomAnchor, constant: 25),
            editButton.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -10),
            editButton.widthAnchor.constraint(equalToConstant: 80),
            editButton.heightAnchor.constraint(equalToConstant: 32)
        ])
        
        let editAction = {
            let selectedIndex = popup.indexOfSelectedItem
            guard selectedIndex >= 0 && selectedIndex < self.requestConfigs.count else { return }
            
            let config = self.requestConfigs[selectedIndex]
            NSApp.stopModal()
            window.close()
            self.showEditConfigDialog(at: selectedIndex, config: config)
        }
        
        let cancelAction = {
            NSApp.stopModal()
        }
        
        class ButtonTarget: NSObject {
            let action: () -> Void
            
            init(action: @escaping () -> Void) {
                self.action = action
            }
            
            @objc func performAction() {
                action()
            }
        }
        
        let editTarget = ButtonTarget(action: editAction)
        let cancelTarget = ButtonTarget(action: cancelAction)
        
        editButton.target = editTarget
        editButton.action = #selector(ButtonTarget.performAction)
        
        cancelButton.target = cancelTarget
        cancelButton.action = #selector(ButtonTarget.performAction)
        
        objc_setAssociatedObject(window, "editTarget", editTarget, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        objc_setAssociatedObject(window, "cancelTarget", cancelTarget, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        
        window.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: window)
        
        if window.isVisible {
            window.close()
        }
    }
    
    func showEditConfigDialog(at index: Int, config: RequestConfig) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "URL 편집"
        window.center()
        window.isReleasedWhenClosed = false
        
        let contentView = NSView()
        window.contentView = contentView
        
        let titleLabel = NSTextField(labelWithString: "URL 정보를 수정하세요.")
        titleLabel.font = NSFont.systemFont(ofSize: 13)
        titleLabel.textColor = .secondaryLabelColor
        
        let nameLabel = NSTextField(labelWithString: "이름:")
        let nameField = NSTextField()
        nameField.stringValue = config.name
        
        let urlLabel = NSTextField(labelWithString: "URL:")
        let urlField = NSTextField()
        urlField.stringValue = config.url
        
        let methodLabel = NSTextField(labelWithString: "HTTP 메서드:")
        let methodPopup = NSPopUpButton()
        methodPopup.addItems(withTitles: ["GET", "POST"])
        methodPopup.selectItem(withTitle: config.method.uppercased())
        
        let bodyLabel = NSTextField(labelWithString: "요청 본문 (POST 시):")
        let bodyField = NSTextView()
        bodyField.font = NSFont.systemFont(ofSize: 12)
        bodyField.isVerticallyResizable = true
        bodyField.isHorizontallyResizable = false
        bodyField.autoresizingMask = [.width]
        bodyField.textContainerInset = NSSize(width: 5, height: 5)
        bodyField.string = config.body ?? ""
        bodyField.isEditable = config.method.uppercased() == "POST"
        
        let scrollView = NSScrollView()
        scrollView.documentView = bodyField
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        
        let intervalLabel = NSTextField(labelWithString: "주기 (초):")
        let intervalField = NSTextField()
        intervalField.stringValue = "\(Int(config.intervalSeconds))"
        
        let updateButton = NSButton(title: "수정", target: nil, action: nil)
        let cancelButton = NSButton(title: "취소", target: nil, action: nil)
        
        updateButton.bezelStyle = .rounded
        cancelButton.bezelStyle = .rounded
        
        [titleLabel, nameLabel, nameField, urlLabel, urlField, methodLabel, methodPopup, bodyLabel, scrollView, intervalLabel, intervalField, updateButton, cancelButton].forEach {
            contentView.addSubview($0)
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        
        NSLayoutConstraint.activate([
            // 제목 레이블
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            // 이름 레이블
            nameLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            // 이름 필드
            nameField.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 5),
            nameField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            nameField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            nameField.heightAnchor.constraint(equalToConstant: 22),
            
            // URL 레이블
            urlLabel.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 15),
            urlLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            urlLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            // URL 필드
            urlField.topAnchor.constraint(equalTo: urlLabel.bottomAnchor, constant: 5),
            urlField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            urlField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            urlField.heightAnchor.constraint(equalToConstant: 22),
            
            // HTTP 메서드 레이블
            methodLabel.topAnchor.constraint(equalTo: urlField.bottomAnchor, constant: 15),
            methodLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            methodLabel.widthAnchor.constraint(equalToConstant: 90),
            
            // HTTP 메서드 팝업
            methodPopup.centerYAnchor.constraint(equalTo: methodLabel.centerYAnchor),
            methodPopup.leadingAnchor.constraint(equalTo: methodLabel.trailingAnchor, constant: 10),
            methodPopup.widthAnchor.constraint(equalToConstant: 100),
            
            // Body 레이블
            bodyLabel.topAnchor.constraint(equalTo: methodLabel.bottomAnchor, constant: 15),
            bodyLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            bodyLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            // Body 텍스트뷰 스크롤뷰
            scrollView.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: 5),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            scrollView.heightAnchor.constraint(equalToConstant: 80),
            
            // 주기 레이블
            intervalLabel.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 15),
            intervalLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            intervalLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            // 주기 필드
            intervalField.topAnchor.constraint(equalTo: intervalLabel.bottomAnchor, constant: 5),
            intervalField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            intervalField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            intervalField.heightAnchor.constraint(equalToConstant: 22),
            
            // 버튼들 - 주기 필드 아래 충분한 공간 확보
            cancelButton.topAnchor.constraint(equalTo: intervalField.bottomAnchor, constant: 25),
            cancelButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            cancelButton.widthAnchor.constraint(equalToConstant: 80),
            cancelButton.heightAnchor.constraint(equalToConstant: 32),
            
            updateButton.topAnchor.constraint(equalTo: intervalField.bottomAnchor, constant: 25),
            updateButton.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -10),
            updateButton.widthAnchor.constraint(equalToConstant: 80),
            updateButton.heightAnchor.constraint(equalToConstant: 32)
        ])
        
        // GET/POST에 따라 필드 활성화
        func updateBodyFieldEnabled() {
            if methodPopup.selectedItem?.title.uppercased() == "POST" {
                bodyField.isEditable = true
                bodyField.backgroundColor = NSColor.textBackgroundColor
            } else {
                bodyField.isEditable = false
                bodyField.backgroundColor = NSColor.windowBackgroundColor
                bodyField.string = ""
            }
        }
        
        updateBodyFieldEnabled()
        
        // Setup method popup action
        class MethodPopupTarget: NSObject {
            let updateBodyFieldEnabled: () -> Void
            init(_ updateFunc: @escaping () -> Void) {
                self.updateBodyFieldEnabled = updateFunc
            }
            @objc func methodChanged(_ sender: NSPopUpButton) {
                updateBodyFieldEnabled()
            }
        }
        
        let methodPopupTarget = MethodPopupTarget(updateBodyFieldEnabled)
        methodPopup.target = methodPopupTarget
        methodPopup.action = #selector(MethodPopupTarget.methodChanged(_:))
        
        objc_setAssociatedObject(window, "methodPopupTarget", methodPopupTarget, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        
        let updateAction = {
            let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let url = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let method = methodPopup.selectedItem?.title.uppercased() ?? "GET"
            let body = method == "POST" ? bodyField.string.trimmingCharacters(in: .whitespacesAndNewlines) : nil
            let intervalText = intervalField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard !name.isEmpty, !url.isEmpty, let interval = Double(intervalText), interval > 0 else {
                self.showErrorAlert("유효하지 않은 입력입니다. 모든 필드를 올바르게 입력해주세요.")
                return
            }
            
            self.requestConfigs[index] = RequestConfig(id: config.id, name: name, url: url, intervalSeconds: interval, method: method, body: body)
            self.saveConfigurations()
            self.restartAllTimers()
            
            NSApp.stopModal()
        }
        
        let cancelAction = {
            NSApp.stopModal()
        }
        
        class ButtonTarget: NSObject {
            let action: () -> Void
            
            init(action: @escaping () -> Void) {
                self.action = action
            }
            
            @objc func performAction() {
                action()
            }
        }
        
        let updateTarget = ButtonTarget(action: updateAction)
        let cancelTarget = ButtonTarget(action: cancelAction)
        
        updateButton.target = updateTarget
        updateButton.action = #selector(ButtonTarget.performAction)
        
        cancelButton.target = cancelTarget
        cancelButton.action = #selector(ButtonTarget.performAction)
        
        objc_setAssociatedObject(window, "updateTarget", updateTarget, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        objc_setAssociatedObject(window, "cancelTarget", cancelTarget, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        
        window.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: window)
        
        // 정리
        window.close()
    }
    
    func showDeleteDialog() {
        guard !requestConfigs.isEmpty else { return }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 150),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "URL 삭제"
        window.center()
        window.isReleasedWhenClosed = false
        
        let contentView = NSView()
        window.contentView = contentView
        
        let titleLabel = NSTextField(labelWithString: "삭제할 항목을 선택하세요.")
        titleLabel.font = NSFont.systemFont(ofSize: 13)
        titleLabel.textColor = .secondaryLabelColor
        
        let selectLabel = NSTextField(labelWithString: "선택:")
        let popup = NSPopUpButton()
        
        for config in requestConfigs {
            popup.addItem(withTitle: "\(config.name) [\(config.method)] - \(config.url)")
        }
        
        let deleteButton = NSButton(title: "삭제", target: nil, action: nil)
        let cancelButton = NSButton(title: "취소", target: nil, action: nil)
        
        deleteButton.bezelStyle = .rounded
        cancelButton.bezelStyle = .rounded
        
        deleteButton.contentTintColor = .systemRed
        
        [titleLabel, selectLabel, popup, deleteButton, cancelButton].forEach {
            contentView.addSubview($0)
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        
        NSLayoutConstraint.activate([
            // 제목 레이블
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            // 선택 레이블
            selectLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            selectLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            selectLabel.widthAnchor.constraint(equalToConstant: 40),
            
            // 드롭다운
            popup.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 18),
            popup.leadingAnchor.constraint(equalTo: selectLabel.trailingAnchor, constant: 10),
            popup.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            popup.heightAnchor.constraint(equalToConstant: 26),
            
            // 버튼들
            cancelButton.topAnchor.constraint(equalTo: popup.bottomAnchor, constant: 25),
            cancelButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            cancelButton.widthAnchor.constraint(equalToConstant: 80),
            cancelButton.heightAnchor.constraint(equalToConstant: 32),
            
            deleteButton.topAnchor.constraint(equalTo: popup.bottomAnchor, constant: 25),
            deleteButton.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -10),
            deleteButton.widthAnchor.constraint(equalToConstant: 80),
            deleteButton.heightAnchor.constraint(equalToConstant: 32)
        ])
        
        let deleteAction = {
            let selectedIndex = popup.indexOfSelectedItem
            guard selectedIndex >= 0 && selectedIndex < self.requestConfigs.count else { return }
            
            // 삭제 확인 다이얼로그
            let confirmAlert = NSAlert()
            confirmAlert.messageText = "URL 삭제 확인"
            confirmAlert.informativeText = "'\(self.requestConfigs[selectedIndex].name)'을(를) 정말 삭제하시겠습니까?"
            confirmAlert.alertStyle = .warning
            confirmAlert.addButton(withTitle: "삭제")
            confirmAlert.addButton(withTitle: "취소")
            
            if confirmAlert.runModal() == .alertFirstButtonReturn {
                let removedId = self.requestConfigs[selectedIndex].id
                self.requestConfigs.remove(at: selectedIndex)
                self.pausedTimers.removeValue(forKey: removedId) // 삭제 시 pause 상태도 제거
                self.results.removeValue(forKey: removedId) // 삭제 시 결과도 제거
                self.saveConfigurations()
                self.restartAllTimers()
            }
            
            NSApp.stopModal()
        }
        
        let cancelAction = {
            NSApp.stopModal()
        }
        
        class ButtonTarget: NSObject {
            let action: () -> Void
            
            init(action: @escaping () -> Void) {
                self.action = action
            }
            
            @objc func performAction() {
                action()
            }
        }
        
        let deleteTarget = ButtonTarget(action: deleteAction)
        let cancelTarget = ButtonTarget(action: cancelAction)
        
        deleteButton.target = deleteTarget
        deleteButton.action = #selector(ButtonTarget.performAction)
        
        cancelButton.target = cancelTarget
        cancelButton.action = #selector(ButtonTarget.performAction)
        
        objc_setAssociatedObject(window, "deleteTarget", deleteTarget, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        objc_setAssociatedObject(window, "cancelTarget", cancelTarget, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        
        window.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: window)
        
        // 정리
        window.close()
    }
    
    func showErrorAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "오류"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "확인")
        alert.runModal()
    }
}

// MARK: - NSMenuDelegate
extension AppDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        menuUpdateTimer?.invalidate()
        menuUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.setupMenu()
        }
    }
    
    func menuDidClose(_ menu: NSMenu) {
        menuUpdateTimer?.invalidate()
        menuUpdateTimer = nil
        // 메뉴 닫힐 때 전체 메뉴 새로고침
        self.setupMenu()
    }
}
