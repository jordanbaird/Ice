//
//  GradientPickerModel.swift
//  Ice
//

import Combine

class GradientPickerModel: ObservableObject {
    @Published var selectedStop: ColorStop?
    var cancellables = Set<AnyCancellable>()
}
