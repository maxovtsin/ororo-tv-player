//
//  SearchViewController.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit
import OroroKit

protocol SearchViewOutput {
    func didPress(model: Searchable)
    func didPressLong(model: Searchable)
}

class SearchViewController: BaseViewController<SearchCollectionViewCellPresenter>,
UISearchControllerDelegate, UISearchResultsUpdating {

    // MARK: - Properties
    private let output: SearchViewOutput

    // MARK: - Life cycle
    init(output: SearchViewOutput) {
        self.output = output
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tap = { [unowned self] searchable in
            self.output.didPress(model: searchable)
        }

        longTap = { [unowned self] searchable in
            self.output.didPressLong(model: searchable)
        }
    }

    // MARK: - UISearchResultsUpdating
    func updateSearchResults(for searchController: UISearchController) {
        guard let text = searchController.searchBar.text else { return }
        if text.isEmpty {
            dataSource.filter { $0 }
        } else {
            dataSource.filter { (items) -> [Searchable] in
                return items.filter { $0.title.lowercased().contains(text.lowercased()) }
            }
        }
    }
}
