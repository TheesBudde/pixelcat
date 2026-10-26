import AppKit
import Combine
import SwiftUI

/// Eigenes Fenster für die Aufgaben: eintragen, umbenennen, entfernen und für jede die Uhrzeit einstellen,
/// zu der sie einmal am Tag daran erinnert.
@MainActor
final class TasksWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let settings: AppSettings
    private var coatWatch: AnyCancellable?

    init(settings: AppSettings) {
        self.settings = settings
    }

    /// Geschlossen: Inhalt verwerfen, damit nichts im Verborgenen weiterläuft
    func windowWillClose(_ notification: Notification) {
        window?.contentView = NSView()
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
                                  styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.titlebarAppearsTransparent = true
            window.minSize = NSSize(width: 480, height: 320)
            window.delegate = self
            window.center()
            self.window = window
            coatWatch = settings.$coat.sink { [weak window] coat in window?.appearance = coat.appearance }
        }
        if !(window?.contentView is NSHostingView<TasksView>) {
            window?.contentView = NSHostingView(rootView: TasksView(settings: settings))
        }
        window?.title = L10n.s("Pixelcat Aufgaben", "Pixelcat Tasks")
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct TasksView: View {
    @ObservedObject var settings: AppSettings
    @State private var newText = ""
    /// Neue Aufgaben starten bei der nächsten vollen Stunde
    @State private var newTime = (Calendar.current.component(.hour, from: Date()) + 1) % 24 * 60

    /// Länger passt nicht gut in die Gedankenblase (drei Zeilen)
    static let maxLength = 45

    private func t(_ de: String, _ en: String) -> String { L10n.s(de, en) }

    var body: some View {
        Form {
            Section {
                Toggle(t("An Aufgaben erinnern", "Remind me of tasks"), isOn: $settings.taskReminders)
                Toggle(t("Auch in Videocalls erinnern", "Also remind me in video calls"),
                       isOn: $settings.tasksDuringCalls)
                hint(settings.hideDuringCalls
                     ? t("Bei Kamera oder Mikrofon bleibt sie versteckt und nur die Blase erscheint am Dock. Bei geteiltem Bildschirm nie.",
                         "With the camera or mic on she stays hidden and only the bubble appears at the Dock. Never while sharing the screen.")
                     : t("Sie versteckt sich in Videocalls nicht (Einstellungen › Rücksicht). Dann erinnert sie sowieso.",
                         "She doesn't hide in video calls (Settings › Being considerate). So she reminds you anyway."))
            } header: {
                SectionTitle(t("Erinnern", "Reminders"), icon: "bell.fill", color: .orange)
            }
            Section {
                HStack(spacing: 10) {
                    TextField("", text: $newText, prompt: Text(t("z. B. „Mama anrufen“", "e.g. “Call mom”")))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(add)
                        .onChange(of: newText) { value in
                            if value.count > Self.maxLength { newText = String(value.prefix(Self.maxLength)) }
                        }
                    timePicker($newTime)
                    Button(t("Hinzufügen", "Add"), action: add)
                        .disabled(newText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                hint(t("Zur Uhrzeit denkt sie einmal am Tag daran. War der Mac da aus, holt sie es bis zu 3 Stunden später nach. Aus Katzenkorb oder Streifzug kommt sie dafür herein.",
                       "She thinks of it once a day at that time. If your Mac was off, she catches up within 3 hours. She comes in from the cat bed or roaming for it."))
            } header: {
                SectionTitle(t("Neue Aufgabe", "New task"), icon: "plus", color: .blue)
            }
            Section {
                if settings.taskItems.isEmpty {
                    hint(t("Noch keine Aufgaben. Trag oben die erste ein.", "No tasks yet. Add the first one above."))
                }
                ForEach($settings.taskItems) { $task in
                    HStack(spacing: 10) {
                        TextField("", text: $task.text)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: task.text) { value in
                                if value.count > Self.maxLength { task.text = String(value.prefix(Self.maxLength)) }
                            }
                        timePicker($task.time)
                        Button {
                            settings.onPreviewTask?(task.id)
                        } label: {
                            Image(systemName: "bubble.left")
                        }
                        .buttonStyle(.borderless)
                        .help(t("Jetzt zeigen", "Show now"))
                        Button {
                            settings.taskItems.removeAll { $0.id == task.id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help(t("Entfernen", "Remove"))
                    }
                }
            } header: {
                SectionTitle(t("Aufgaben", "Tasks"), icon: "checklist", color: .green)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(.top, 18)
        .background(PixelBackdrop(coat: settings.coat))
        .environment(\.colorScheme, settings.coat.colorScheme)
        .frame(minWidth: 480, minHeight: 320)
        .id(settings.language)
        // Nach Uhrzeit geordnet (beim Öffnen – nicht mitten im Ändern einer Uhrzeit)
        .onAppear { sortByTime() }
    }

    private func add() {
        let text = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        settings.taskItems.append(TaskItem(text: text, time: newTime))
        sortByTime()
        newText = ""
    }

    private func sortByTime() {
        let sorted = settings.taskItems.sorted { $0.time < $1.time }
        if sorted != settings.taskItems { settings.taskItems = sorted }
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }

    private func timePicker(_ minutes: Binding<Int>) -> some View {
        DatePicker("", selection: clockBinding(minutes), displayedComponents: .hourAndMinute)
            .labelsHidden()
            .fixedSize()
    }
}
