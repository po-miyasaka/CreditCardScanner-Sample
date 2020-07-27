//
//  ViewController.swift
//  CardScanner-Sample
//
//  Created by miyasaka on 2020/07/27.
//  Copyright © 2020 miyasaka. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if #available(iOS 13.0, *) {
            let nvc = UINavigationController(rootViewController: CreditCardReaderViewController())
            nvc.modalPresentationStyle = .fullScreen
            present(nvc, animated: true, completion: nil)
        }
    }


}

