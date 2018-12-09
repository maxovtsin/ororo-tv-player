//
//  GenericCollectionViewDataSource.swift
//  Ororo-Kit
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit

public final class GenericCollectionViewDataSource<PresenterType>
    : NSObject, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout
where PresenterType: CollectionViewCellPresenter {

    public enum UpdateType: Int {
        case initialLoad
        case reload
        case update
    }

    // MARK: - Properties
    private var original: [PresenterType.ModelType] = []
    private var filtered: [PresenterType.ModelType] = []
    private var didPress: ((PresenterType.ModelType) -> Void)?

    private var collectionView: UICollectionView!

    // MARK: - Public interface
    public func configure(with collectionView: UICollectionView,
                          didPress: @escaping (PresenterType.ModelType) -> Void) {
        self.collectionView = collectionView
        collectionView.dataSource = self
        collectionView.delegate = self
        self.didPress = didPress
        PresenterType.registerCells(collectionView)
    }

    public func filter(_ block: ([PresenterType.ModelType]) -> [PresenterType.ModelType]) {
        let new = block(original)
        let changes = diff(old: filtered, new: new)
        performBatchUpdate(changes: changes,
                           updateType: .reload,
                           before: {
                            self.filtered = new
        }, updated: {})
    }

    public func update(items: [PresenterType.ModelType]?) {

        let changes = diff(old: filtered, new: items ?? [])

        performBatchUpdate(changes: changes,
                           updateType: .reload,
                           before: {

                            if let items = items {
                                self.original = items
                                self.filtered = items
                            } else {
                                self.original.removeAll()
                                self.filtered.removeAll()
                            }
        }, updated: {})
    }

    public func performBatchUpdate(changes: [Diff.Operation],
                                   updateType: UpdateType,
                                   before: @escaping () -> Void,
                                   updated: @escaping () -> Void) {

        let wantsReloadData = updateType != .initialLoad

        if wantsReloadData {
            self.collectionView.performBatchUpdates({
                before()

                var insertions = [IndexPath]()
                var deletions = [IndexPath]()
                var moves = [(IndexPath, IndexPath)]()

                for change in changes {
                    switch change {
                    case let .insertion(index):
                        insertions.append(IndexPath(row: index, section: 0))
                    case let .deletion(index):
                        deletions.append(IndexPath(row: index, section: 0))
                    case let .move(from, to):
                        moves.append((
                            IndexPath(row: from, section: 0),
                            IndexPath(row: to, section: 0)))
                    }
                }

                self.collectionView.deleteItems(at: deletions)
                self.collectionView.insertItems(at: insertions)

                for move in moves {
                    self.collectionView.moveItem(at: move.0, to: move.1)
                }

            }, completion: { _ in
                updated()
            })

        } else {
            before()
            collectionView.reloadData()
            updated()
        }
    }

    public func model(at indexPath: IndexPath) -> PresenterType.ModelType {
        return filtered[indexPath.row]
    }

    public func collectionView(_ collectionView: UICollectionView,
                               numberOfItemsInSection section: Int) -> Int {
        return filtered.count
    }

    public func collectionView(_ collectionView: UICollectionView,
                               cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell: PresenterType.CellType = collectionView
            .dequeueReusableCell(withClass: PresenterType.CellType.self,
                                 forIndexPath: indexPath)
        PresenterType.configure(cell: cell,
                                model: filtered[indexPath.row])
        return cell
    }

    public func collectionView(_ collectionView: UICollectionView,
                               didSelectItemAt indexPath: IndexPath) {
        didPress?(filtered[indexPath.row])
    }

    public func collectionView(_ collectionView: UICollectionView,
                               layout collectionViewLayout: UICollectionViewLayout,
                               sizeForItemAt indexPath: IndexPath) -> CGSize {
        let maximumWidth = collectionView.bounds.width
        let size = PresenterType.sizeForCell(maximumWidth: maximumWidth)
        return size
    }

    public func collectionView(_ collectionView: UICollectionView,
                               layout collectionViewLayout: UICollectionViewLayout,
                               minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        let maximumWidth = collectionView.bounds.width
        return PresenterType.minimumLineSpacingForSection(maximumWidth: maximumWidth)
    }

    public func collectionView(_ collectionView: UICollectionView,
                               layout collectionViewLayout: UICollectionViewLayout,
                               minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        return 0.0
    }
}
