//
//  CustomGradientPickerModel.swift
//  Ice
//

import Combine

class CustomGradientPickerModel: ObservableObject {
    @Published var selectedStop: ColorStop?
    @Published var zOrderedStops: [ColorStop]

    var cancellables = Set<AnyCancellable>()

    init(zOrderedStops: [ColorStop]) {
        self.zOrderedStops = zOrderedStops
    }
}
