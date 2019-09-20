//
//  SubtitleParserTests.swift
//  Ororo-KitTests
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import XCTest
@testable import OroroKit

class SubtitleParserTests: XCTestCase {

    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func test_GivenStringWithVTT_ThenItShouldBeParsed() {
        let payload = """
                        WEBVTT\n\n
                        1\n00:02:51.000 --> 00:02:53.000\nCome, </br>come!<br>\n\n
                        2\n00:02:57.000 --> 00:02:59.000\n</i>Please!<i>\n\n
                      """

        let intervals = SubtitleParser.parse(payload: payload)

        XCTAssert(intervals.count == 2, "Must be equal to 3")

        let interval1 = intervals[0]
        XCTAssert(interval1.text == "Come, come!", "Text is wrong")
        XCTAssert(interval1.from == 171, "From label is wrong")
        XCTAssert(interval1.to == 173, "To label is wrong")

        let interval2 = intervals[1]
        XCTAssert(interval2.text == "Please!", "Text is wrong")
        XCTAssert(interval2.from == 177, "From label is wrong")
        XCTAssert(interval2.to == 179, "To label is wrong")
    }
}
