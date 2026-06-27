//
//  HeaderFilterBar.swift
//  DuckSort
//
//  Redesigned horizontal culling and filter menu bar above the photo library grid.
//

import SwiftUI
import AppKit

struct HeaderFilterBar: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @State private var showFilterPopover = false

    var body: some View {
        HStack(spacing: Theme.Space.s12) {
            // Sort controls (Name / Date toggles) on the left
            sortControls

            Spacer()

            // Filter button that opens the popover on the right
            Button {
                showFilterPopover.toggle()
            } label: {
                ZStack {
                    let hasActiveFilters = viewModel.activeFilterCount > 0 && viewModel.isFilterPopoverEnabled
                    Circle()
                        .fill(hasActiveFilters ? Theme.Color.accent : Color.primary.opacity(0.06))
                        .frame(width: 28, height: 28)
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: hasActiveFilters ? .bold : .regular))
                        .foregroundStyle(hasActiveFilters ? Theme.Color.textInverse : Theme.Color.textSecondary)
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showFilterPopover, arrowEdge: .bottom) {
                FilterPopoverContent(viewModel: viewModel)
            }
            .help("Filter Options")
        }
        .padding(.horizontal, Theme.Space.s16)
        .padding(.vertical, Theme.Space.s10)
        .background(Theme.Color.background) // Matches main grid view background
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Theme.Color.separator), // Blends clean horizontal separator
            alignment: .bottom
        )
        .zIndex(1000)
    }

    // MARK: - Sort Controls
    private var sortControls: some View {
        HStack(spacing: Theme.Space.s8) {
            Text("Sort:")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textSecondary)

            // Date Sort Button
            Button {
                withAnimation(.smooth(duration: 0.2)) {
                    viewModel.sortOrder = .date
                }
            } label: {
                Text("Date")
                    .font(Theme.Font.bodyBold)
                    .padding(.horizontal, Theme.Space.s10)
                    .padding(.vertical, Theme.Space.s4)
                    .background(viewModel.sortOrder == .date ? Theme.Color.accent : Color.primary.opacity(0.04))
                    .foregroundStyle(viewModel.sortOrder == .date ? Theme.Color.textInverse : Theme.Color.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.m))
            }
            .buttonStyle(.plain)

            // Name Sort Button
            Button {
                withAnimation(.smooth(duration: 0.2)) {
                    viewModel.sortOrder = .name
                }
            } label: {
                Text("Name")
                    .font(Theme.Font.bodyBold)
                    .padding(.horizontal, Theme.Space.s10)
                    .padding(.vertical, Theme.Space.s4)
                    .background(viewModel.sortOrder == .name ? Theme.Color.accent : Color.primary.opacity(0.04))
                    .foregroundStyle(viewModel.sortOrder == .name ? Theme.Color.textInverse : Theme.Color.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.m))
            }
            .buttonStyle(.plain)

            // Direction Toggle Button
            Button {
                withAnimation(.smooth(duration: 0.2)) {
                    viewModel.sortDirection = viewModel.sortDirection == .ascending ? .descending : .ascending
                }
            } label: {
                Image(systemName: viewModel.sortDirection == .ascending ? "arrow.up" : "arrow.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.Color.accent)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.m))
            .help("Toggle Sort Direction")
        }
    }
}

// MARK: - Popover Filter Panel Content
struct FilterPopoverContent: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header: Filter title, Reset, Toggle
            HStack(spacing: 8) {
                Text("Filter")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Color.textPrimary)

                Spacer()

                // Reset button
                Button {
                    withAnimation(.smooth(duration: 0.2)) {
                        viewModel.resetFilterPopover()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Reset all filters")
                .padding(.trailing, 4)

                // Master Toggle Switch
                Toggle("", isOn: $viewModel.isFilterPopoverEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()
                .background(Theme.Color.separator)

            // Content List of filters
            ScrollView {
                VStack(spacing: 12) {
                    // 1. Edited Filter Row
                    FilterRow(
                        isActive: $viewModel.filterEditedActive,
                        icon: "slider.horizontal.3",
                        title: "Edited"
                    ) {
                        Picker("", selection: $viewModel.filterEdited) {
                            Text("Include").tag(PhotoLibraryViewModel.BinaryFilter.include)
                            Text("Exclude").tag(PhotoLibraryViewModel.BinaryFilter.exclude)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 100)
                        .controlSize(.small)
                    }

                    Divider()
                        .background(Theme.Color.separator.opacity(0.5))

                    // 2. RAW Filter Row
                    FilterRow(
                        isActive: $viewModel.filterRawActive,
                        icon: "r.square",
                        title: "RAW"
                    ) {
                        Picker("", selection: $viewModel.filterRaw) {
                            Text("Include").tag(PhotoLibraryViewModel.BinaryFilter.include)
                            Text("Exclude").tag(PhotoLibraryViewModel.BinaryFilter.exclude)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 100)
                        .controlSize(.small)
                    }

                    Divider()
                        .background(Theme.Color.separator.opacity(0.5))

                    // 3. Rating Filter Row
                    FilterRow(
                        isActive: $viewModel.filterRatingActive,
                        icon: "star",
                        title: "Rating"
                    ) {
                        HStack(spacing: 4) {
                            // Star Value Dropdown
                            Picker("", selection: $viewModel.filterRatingValue) {
                                Text("Unrated").tag(0)
                                Text("★").tag(1)
                                Text("★★").tag(2)
                                Text("★★★").tag(3)
                                Text("★★★★").tag(4)
                                Text("★★★★★").tag(5)
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: 100)
                            .controlSize(.small)

                            // Option button ... (Rating Condition)
                            Menu {
                                ForEach(PhotoLibraryViewModel.RatingCondition.allCases, id: \.self) { condition in
                                    Button(condition.rawValue) {
                                        viewModel.filterRatingCondition = condition
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.Color.accent)
                            }
                            .menuStyle(.borderlessButton)
                            .frame(width: 22, height: 22)
                            .help("Condition: \(viewModel.filterRatingCondition.rawValue)")
                        }
                    }

                    Divider()
                        .background(Theme.Color.separator.opacity(0.5))

                    // 4. Flag Filter Row
                    FilterRow(
                        isActive: $viewModel.filterFlagActive,
                        icon: "flag",
                        title: "Flag"
                    ) {
                        Picker("", selection: $viewModel.filterFlag) {
                            Text("All Flags").tag(PhotoLibraryViewModel.FlagFilter.all)
                            Text("Flagged").tag(PhotoLibraryViewModel.FlagFilter.flagged)
                            Text("Rejected").tag(PhotoLibraryViewModel.FlagFilter.rejected)
                            Text("Unflagged").tag(PhotoLibraryViewModel.FlagFilter.unflagged)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 110)
                        .controlSize(.small)
                    }

                    Divider()
                        .background(Theme.Color.separator.opacity(0.5))

                    // 5. File Name Filter Row
                    VStack(alignment: .leading, spacing: 6) {
                        FilterRow(
                            isActive: $viewModel.filterNameActive,
                            icon: "doc",
                            title: "File Name"
                        ) {
                            Picker("", selection: $viewModel.nameFilterCondition) {
                                Text("Contains").tag(PhotoLibraryViewModel.NameCondition.contains)
                                Text("Matches").tag(PhotoLibraryViewModel.NameCondition.matches)
                                Text("Starts with").tag(PhotoLibraryViewModel.NameCondition.startsWith)
                                Text("Ends with").tag(PhotoLibraryViewModel.NameCondition.endsWith)
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: 110)
                            .controlSize(.small)
                        }

                        if viewModel.filterNameActive {
                            TextField("Text", text: $viewModel.nameFilterQuery)
                                .textFieldStyle(.plain)
                                .font(Theme.Font.body)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Theme.Color.cellBackground)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.s))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.Radius.s)
                                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                )
                                .padding(.leading, 32)
                                .padding(.trailing, 8)
                        }
                    }

                    Divider()
                        .background(Theme.Color.separator.opacity(0.5))

                    // 6. Date Filter Row
                    VStack(alignment: .leading, spacing: 6) {
                        FilterRow(
                            isActive: $viewModel.filterDateActive,
                            icon: "calendar",
                            title: "Date"
                        ) {
                            Spacer()
                        }

                        if viewModel.filterDateActive {
                            HStack(spacing: 6) {
                                DatePicker("", selection: $viewModel.filterStartDate, displayedComponents: .date)
                                    .labelsHidden()
                                    .controlSize(.small)
                                    .frame(maxWidth: .infinity)

                                Text("to")
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.Color.textSecondary)

                                DatePicker("", selection: $viewModel.filterEndDate, displayedComponents: .date)
                                    .labelsHidden()
                                    .controlSize(.small)
                                    .frame(maxWidth: .infinity)
                            }
                            .padding(.leading, 32)
                            .padding(.trailing, 8)
                        }
                    }


                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .frame(width: 320)
        .padding(.bottom, 12)
    }
}

// MARK: - Row Helper Component
struct FilterRow<Content: View>: View {
    @Binding var isActive: Bool
    let icon: String
    let title: String
    let content: () -> Content

    var body: some View {
        HStack(spacing: 8) {
            // Checkbox
            Button {
                withAnimation(.smooth(duration: 0.15)) {
                    isActive.toggle()
                }
            } label: {
                Image(systemName: isActive ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundStyle(isActive ? Theme.Color.accent : Theme.Color.textSecondary)
            }
            .buttonStyle(.plain)

            // Icon
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Theme.Color.textSecondary)
                .frame(width: 16)

            // Title
            Text(title)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.textPrimary)

            Spacer()

            // Control Content (disabled if inactive)
            content()
                .disabled(!isActive)
                .opacity(isActive ? 1.0 : 0.5)
        }
        .frame(height: 28)
    }
}
