// 用户自建推荐店铺表单
// 搜索高德候选 → 选择门店入库

import SwiftUI
import CoreLocation

struct UserAddRestaurantSheet: View {
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var locationManager: LocationManager
    let initialName: String?  // 从搜索无结果引导过来时自动注入的店铺名称
    let onSuccess: (_ restaurantId: String?) -> Void  // 添加成功后回调，传回 restaurant_id 用于地图定位

    @AppStorage("user_add_recent_cities") private var recentCitiesStore = ""

    @State private var restaurantName = ""
    @State private var selectedCity = UserAddCityCatalog.nationwide

    @State private var detectedCity: String?
    @State private var detectedProvince: String?
    @State private var isResolvingLocation = false
    @State private var hasAppliedDetectedCity = false
    @State private var hasManuallyChangedCity = false
    @State private var lastGeocodedLocation: CLLocation?

    @State private var isSearching = false
    @State private var candidates: [RestaurantCandidate] = []
    @State private var searchError: String?
    @State private var hasSearched = false

    @State private var isSubmitting = false
    @State private var successMessage: String?

    @State private var showCityPicker = false
    @State private var previewImageURL: String?
    @State private var showImagePreview = false

    private var trimmedRestaurantName: String {
        restaurantName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSearch: Bool {
        trimmedRestaurantName.count >= 2 && !isSearching
    }

    private var selectedSearchCity: String {
        selectedCity == UserAddCityCatalog.nationwide ? "" : selectedCity
    }

    private var recentCities: [String] {
        recentCitiesStore
            .split(separator: "|")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private var locationHintText: String {
        if let detectedCity {
            if let detectedProvince,
               !detectedProvince.isEmpty,
               detectedProvince != detectedCity {
                return "已定位到 \(detectedProvince) · \(detectedCity)"
            }
            return "已定位到 \(detectedCity)"
        }
        if isResolvingLocation {
            return "正在获取当前位置"
        }
        if let errorMessage = locationManager.errorMessage, !errorMessage.isEmpty {
            return errorMessage
        }
        return "未获取到定位，可切换到全国或手动选城市"
    }

    private var resultsSubtitle: String {
        if candidates.contains(where: { $0.distance_meters != nil }) {
            return "已结合当前位置按距离优先排序"
        }
        if selectedSearchCity.isEmpty {
            return "当前为全国范围搜索"
        }
        return "当前范围：\(selectedCity)"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 22) {
                        heroSection
                        searchFormCard

                        if let error = searchError {
                            messageBanner(
                                icon: "exclamationmark.triangle.fill",
                                color: .orange,
                                text: error
                            )
                        }

                        if hasSearched {
                            resultsSection
                        }

                        if let msg = successMessage {
                            messageBanner(
                                icon: "checkmark.circle.fill",
                                color: .green,
                                text: msg
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("搜索店铺添加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .task {
                // 如果从搜索无结果引导过来，自动注入店铺名称
                if let name = initialName, !name.isEmpty {
                    restaurantName = name
                }
                locationManager.requestPermission()
                await resolveCurrentCityIfNeeded(force: true)
            }
            .onChange(of: locationManager.locationUpdateCount) { _, _ in
                Task { await resolveCurrentCityIfNeeded() }
            }
            .sheet(isPresented: $showCityPicker) {
                CityPickerSheet(
                    selectedCity: selectedCity,
                    currentCity: detectedCity,
                    currentProvince: detectedProvince,
                    recentCities: recentCities
                ) { city in
                    applySelectedCity(city, isManual: true)
                }
            }
            .sheet(isPresented: $showImagePreview) {
                ImagePreviewSheet(imageURL: previewImageURL)
            }
        }
    }

    private var heroSection: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [DS.Color.brand.opacity(0.18), Color.white],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 78, height: 78)

                Image(systemName: "mappin.and.ellipse.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(DS.Color.brand)
            }

            Text("搜索店铺添加")
                .font(.title2.bold())

            Text("优先搜索附近门店，可切换地区")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.95)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 4)
    }

    private var searchFormCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("查找店铺")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("店铺名称")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("输入店铺名称，例如 马厂老火锅", text: $restaurantName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(DS.Color.separator.opacity(0.12), lineWidth: 0.8)
                    }
                    .submitLabel(.search)
                    .onSubmit { Task { await searchRestaurants() } }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("所在城市")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button {
                    showCityPicker = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: detectedCity == selectedCity ? "location.fill" : "mappin.circle")
                            .foregroundColor(DS.Color.brand)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(selectedCity)
                                .font(.body.weight(.semibold))
                                .foregroundColor(.primary)

                            Text(locationHintText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(DS.Color.separator.opacity(0.12), lineWidth: 0.8)
                    }
                }
                .buttonStyle(.plain)
            }

            Button(action: { Task { await searchRestaurants() } }) {
                HStack(spacing: 10) {
                    if isSearching {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.82)
                            .tint(.white)
                    } else {
                        Image(systemName: "magnifyingglass")
                    }

                    Text(isSearching ? "查找中..." : "查找店铺")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(canSearch ? DS.Color.brand : Color.gray.opacity(0.35))
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .disabled(!canSearch)
        }
        .padding(18)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(DS.Color.separator.opacity(0.10), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.05), radius: 14, y: 6)
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if candidates.isEmpty {
                emptyStateView
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("选择一家最接近的店（共 \(candidates.count) 条）")
                        .font(.headline)
                    Text(resultsSubtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                ForEach(candidates) { candidate in
                    UserRestaurantCandidateCard(
                        candidate: candidate,
                        isSubmitting: isSubmitting,
                        onPreviewImage: {
                            guard let photoURL = candidate.photo_url, !photoURL.isEmpty else { return }
                            previewImageURL = photoURL
                            showImagePreview = true
                        },
                        onSelect: { Task { await addRestaurant(candidate) } }
                    )
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 10) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 32))
                .foregroundColor(.gray.opacity(0.5))

            Text("暂时没找到这家店")
                .font(.subheadline.weight(.semibold))

            Text("可以试试更短的主店名、切换城市/省份，或补全分店名再搜")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .padding(.horizontal, 18)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DS.Color.separator.opacity(0.10), lineWidth: 0.8)
        }
    }

    private func messageBanner(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @MainActor
    private func searchRestaurants() async {
        guard trimmedRestaurantName.count >= 2 else { return }

        isSearching = true
        searchError = nil
        successMessage = nil
        hasSearched = false
        candidates = []

        do {
            candidates = try await APIService.shared.searchUserRestaurant(
                name: trimmedRestaurantName,
                city: selectedSearchCity,
                userId: authState.userId,
                location: locationManager.userLocation,
                limit: 50
            )
            hasSearched = true
            updateRecentCities(with: selectedCity)
        } catch {
            searchError = error.localizedDescription
        }

        isSearching = false
    }

    @MainActor
    private func addRestaurant(_ candidate: RestaurantCandidate) async {
        guard candidate.is_added != true else {
            searchError = "该店铺已在我的推荐中，无需重复添加"
            return
        }

        isSubmitting = true
        searchError = nil

        do {
            let resp = try await APIService.shared.createUserRestaurant(
                userId: authState.userId,
                candidate: candidate
            )
            if let index = candidates.firstIndex(where: { $0.id == candidate.id }) {
                let updated = RestaurantCandidate(
                    amap_id: candidate.amap_id,
                    name: candidate.name,
                    address: candidate.address,
                    city: candidate.city,
                    latitude: candidate.latitude,
                    longitude: candidate.longitude,
                    category_raw: candidate.category_raw,
                    category_mapped: candidate.category_mapped,
                    avg_price: candidate.avg_price,
                    photo_url: candidate.photo_url,
                    tel: candidate.tel,
                    distance_meters: candidate.distance_meters,
                    is_added: true
                )
                candidates[index] = updated
            }
            successMessage = resp.message
            updateRecentCities(with: candidate.city)
            onSuccess(resp.restaurant_id)

            try? await Task.sleep(nanoseconds: 1_200_000_000)
            dismiss()
        } catch {
            searchError = error.localizedDescription
        }

        isSubmitting = false
    }

    @MainActor
    private func resolveCurrentCityIfNeeded(force: Bool = false) async {
        guard let coordinate = locationManager.userLocation else { return }

        let currentLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        if !force,
           let lastGeocodedLocation,
           currentLocation.distance(from: lastGeocodedLocation) < 300 {
            return
        }

        lastGeocodedLocation = currentLocation
        isResolvingLocation = true

        defer { isResolvingLocation = false }

        do {
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(
                currentLocation,
                preferredLocale: Locale(identifier: "zh_CN")
            )
            guard let placemark = placemarks.first else { return }

            let city = UserAddCityCatalog.normalize(placemark.locality ?? placemark.subAdministrativeArea)
            let province = UserAddCityCatalog.normalize(placemark.administrativeArea)

            detectedCity = city ?? province
            detectedProvince = province

            if !hasAppliedDetectedCity,
               !hasManuallyChangedCity,
               let preferredCity = city ?? province {
                selectedCity = preferredCity
                hasAppliedDetectedCity = true
            }
        } catch {
            // 反查失败时保留现有城市选择，不额外打断用户流程。
        }
    }

    private func applySelectedCity(_ city: String, isManual: Bool) {
        selectedCity = city
        if isManual {
            hasManuallyChangedCity = true
        }
        updateRecentCities(with: city)
    }

    private func updateRecentCities(with city: String) {
        guard city != UserAddCityCatalog.nationwide else { return }

        var values = recentCities.filter { $0 != city }
        values.insert(city, at: 0)
        recentCitiesStore = Array(values.prefix(6)).joined(separator: "|")
    }
}

private struct UserRestaurantCandidateCard: View {
    let candidate: RestaurantCandidate
    let isSubmitting: Bool
    let onPreviewImage: () -> Void
    let onSelect: () -> Void

    private var isAdded: Bool {
        candidate.is_added == true
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            CandidateImageView(
                photoURL: candidate.photo_url,
                onTap: onPreviewImage
            )

            VStack(alignment: .leading, spacing: 7) {
                Text(candidate.name)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(2)

                Text(candidate.address.isEmpty ? "暂无详细地址" : candidate.address)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                FlowTagRow(tags: tags)
            }

            Spacer(minLength: 10)

            Button(action: onSelect) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isAdded ? Color(.systemGray5) : DS.Color.brand)
                        .frame(width: 64, height: 42)

                    if isSubmitting && !isAdded {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: isAdded ? "checkmark" : "plus")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(isAdded ? .secondary : .white)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting || isAdded)
        }
        .padding(14)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DS.Color.separator.opacity(0.10), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
    }

    private var tags: [CandidateTag] {
        var result: [CandidateTag] = []

        if candidate.is_added == true {
            result.append(.init(text: "已添加", tint: .success))
        }
        if !candidate.city.isEmpty {
            result.append(.init(text: candidate.city, tint: .secondary))
        }
        if !candidate.category_mapped.isEmpty {
            result.append(.init(text: candidate.category_mapped, tint: .brand))
        }
        if let avgPrice = candidate.avg_price {
            result.append(.init(text: "人均¥\(avgPrice)", tint: .secondary))
        }
        if let distanceText = candidate.distanceText {
            result.append(.init(text: distanceText, tint: .brand))
        }

        return result
    }
}

private struct CandidateImageView: View {
    let photoURL: String?
    let onTap: () -> Void

    var body: some View {
        Group {
            if let photoURL, !photoURL.isEmpty {
                Button(action: onTap) {
                    AsyncImage(url: URL(string: photoURL)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            placeholder
                        }
                    }
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.black.opacity(0.55), in: Circle())
                            .padding(8)
                    }
                }
                .buttonStyle(.plain)
            } else {
                placeholder
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [DS.Color.brand.opacity(0.16), Color.orange.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "fork.knife.circle.fill")
                .font(.system(size: 28))
                .foregroundColor(DS.Color.brand)
        }
    }
}

private struct CandidateTag: Identifiable {
    let id = UUID()
    let text: String
    let tint: CandidateTagTint
}

private enum CandidateTagTint {
    case brand
    case secondary
    case success

    var foregroundColor: Color {
        switch self {
        case .brand:
            return DS.Color.brand
        case .secondary:
            return .secondary
        case .success:
            return .green
        }
    }

    var backgroundColor: Color {
        switch self {
        case .brand:
            return DS.Color.brand.opacity(0.10)
        case .secondary:
            return DS.Color.surfaceAlt
        case .success:
            return Color.green.opacity(0.12)
        }
    }
}

private struct FlowTagRow: View {
    let tags: [CandidateTag]

    var body: some View {
        if tags.isEmpty {
            EmptyView()
        } else {
            FlexibleTagLayout(spacing: 8, lineSpacing: 8) {
                ForEach(tags) { tag in
                    Text(tag.text)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(tag.tint.foregroundColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(tag.tint.backgroundColor, in: Capsule())
                }
            }
        }
    }
}

private struct CityPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let selectedCity: String
    let currentCity: String?
    let currentProvince: String?
    let recentCities: [String]
    let onSelect: (String) -> Void

    @State private var searchText = ""

    private var filteredCities: [String] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return [] }

        return UserAddCityCatalog.allCities.filter { city in
            city.localizedCaseInsensitiveContains(keyword)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    searchBar

                    if !filteredCities.isEmpty || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        citySearchResults
                    } else {
                        cityOverview
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .navigationTitle("选择城市")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("搜索城市/省份", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var citySearchResults: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(filteredCities.isEmpty ? "未找到匹配项" : "搜索结果")
                .font(.headline)

            if filteredCities.isEmpty {
                Text("试试输入更短的城市名，例如“西藏”“拉萨”“上海”")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(filteredCities, id: \.self) { city in
                        cityListRow(city)
                    }
                }
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(DS.Color.separator.opacity(0.10), lineWidth: 0.8)
                }
            }
        }
    }

    private var cityOverview: some View {
        VStack(alignment: .leading, spacing: 24) {
            CityGridSection(
                title: "定位/历史访问城市",
                items: locationAndRecentCities,
                selectedCity: selectedCity,
                isLocationSection: true,
                onSelect: selectCity
            )

            CityGridSection(
                title: "热门城市",
                items: UserAddCityCatalog.hotCities,
                selectedCity: selectedCity,
                onSelect: selectCity
            )

            CityGridSection(
                title: "省份/自治区/特别行政区",
                items: UserAddCityCatalog.provincesAndRegions,
                selectedCity: selectedCity,
                onSelect: selectCity
            )

            ForEach(UserAddCityCatalog.cityGroups, id: \.title) { group in
                CityGridSection(
                    title: group.title,
                    items: group.cities,
                    selectedCity: selectedCity,
                    onSelect: selectCity
                )
            }
        }
    }

    private var locationAndRecentCities: [String] {
        var values = [UserAddCityCatalog.nationwide]

        if let currentCity, !currentCity.isEmpty {
            values.append(currentCity)
        } else if let currentProvince, !currentProvince.isEmpty {
            values.append(currentProvince)
        }

        for city in recentCities where !values.contains(city) {
            values.append(city)
        }

        return values
    }

    private func cityListRow(_ city: String) -> some View {
        Button {
            selectCity(city)
        } label: {
            HStack {
                Text(city)
                    .foregroundColor(.primary)
                Spacer()
                if city == selectedCity {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(DS.Color.brand)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Divider()
                .padding(.leading, 16)
                .opacity(city == filteredCities.last ? 0 : 1)
        }
    }

    private func selectCity(_ city: String) {
        onSelect(city)
        dismiss()
    }
}

private struct CityGridSection: View {
    let title: String
    let items: [String]
    let selectedCity: String
    var isLocationSection = false
    let onSelect: (String) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(items, id: \.self) { city in
                    Button {
                        onSelect(city)
                    } label: {
                        HStack(spacing: 6) {
                            if isLocationSection && city != UserAddCityCatalog.nationwide && city == items.first(where: { $0 != UserAddCityCatalog.nationwide }) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 11, weight: .bold))
                            }

                            Text(city)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                        }
                        .foregroundColor(city == selectedCity ? DS.Color.brand : .primary)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .padding(.horizontal, 8)
                        .background(
                            city == selectedCity ? DS.Color.brand.opacity(0.12) : Color(.systemBackground),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(
                                    city == selectedCity ? DS.Color.brand.opacity(0.30) : DS.Color.separator.opacity(0.12),
                                    lineWidth: 0.8
                                )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct FlexibleTagLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += rowHeight + lineSpacing
                rowHeight = 0
            }

            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
        }

        return CGSize(
            width: proposal.width ?? currentX,
            height: currentY + rowHeight
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > bounds.maxX, currentX > bounds.minX {
                currentX = bounds.minX
                currentY += rowHeight + lineSpacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
        }
    }
}

private enum UserAddCityCatalog {
    static let nationwide = "全国"

    static let hotCities = [
        "上海", "北京", "广州", "深圳", "杭州", "成都",
        "重庆", "苏州", "南京", "武汉", "长沙", "西安",
        "青岛", "厦门", "三亚"
    ]

    static let provincesAndRegions = [
        "北京", "上海", "天津", "重庆",
        "河北", "山西", "辽宁", "吉林", "黑龙江",
        "江苏", "浙江", "安徽", "福建", "江西", "山东",
        "河南", "湖北", "湖南", "广东", "海南",
        "四川", "贵州", "云南", "陕西", "甘肃", "青海",
        "内蒙古", "广西", "西藏", "宁夏", "新疆",
        "香港", "澳门", "台湾"
    ]

    static let cityGroups: [(title: String, cities: [String])] = [
        (
            "华东",
            [
                "上海", "南京", "苏州", "无锡", "常州", "南通",
                "扬州", "徐州", "杭州", "宁波", "温州", "绍兴",
                "嘉兴", "金华", "湖州", "台州", "合肥", "芜湖",
                "福州", "厦门", "泉州", "济南", "青岛", "烟台",
                "潍坊", "临沂", "南昌", "赣州"
            ]
        ),
        (
            "华南",
            [
                "广州", "深圳", "佛山", "东莞", "珠海", "中山",
                "惠州", "汕头", "南宁", "桂林", "海口", "三亚",
                "香港", "澳门"
            ]
        ),
        (
            "华中",
            [
                "武汉", "长沙", "郑州", "洛阳", "开封", "南阳",
                "宜昌", "襄阳", "株洲", "湘潭"
            ]
        ),
        (
            "华北",
            [
                "北京", "天津", "石家庄", "唐山", "保定", "太原",
                "大同", "呼和浩特", "包头", "鄂尔多斯"
            ]
        ),
        (
            "东北",
            [
                "沈阳", "大连", "鞍山", "长春", "吉林", "哈尔滨",
                "齐齐哈尔", "牡丹江"
            ]
        ),
        (
            "西南",
            [
                "成都", "重庆", "绵阳", "贵阳", "遵义", "昆明",
                "大理", "丽江", "拉萨", "日喀则", "林芝",
                "山南", "昌都", "西双版纳"
            ]
        ),
        (
            "西北",
            [
                "西安", "咸阳", "兰州", "西宁", "银川", "乌鲁木齐",
                "喀什", "伊宁", "阿勒泰", "库尔勒"
            ]
        )
    ]

    static let allCities: [String] = unique(
        [nationwide] + provincesAndRegions + hotCities + cityGroups.flatMap(\.cities)
    )

    static func normalize(_ name: String?) -> String? {
        guard let rawName = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawName.isEmpty else {
            return nil
        }

        let suffixes = [
            "特别行政区", "维吾尔自治区", "壮族自治区", "回族自治区",
            "自治区", "省", "市"
        ]

        for suffix in suffixes where rawName.hasSuffix(suffix) {
            return String(rawName.dropLast(suffix.count))
        }

        return rawName
    }

    private static func unique(_ cities: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for city in cities where !seen.contains(city) {
            seen.insert(city)
            result.append(city)
        }

        return result
    }
}
