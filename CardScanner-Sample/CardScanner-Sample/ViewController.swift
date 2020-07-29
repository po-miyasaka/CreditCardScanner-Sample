//
//  ViewController.swift
//  CardScanner-Sample
//
//  Created by miyasaka on 2020/07/27.
//  Copyright © 2020 miyasaka. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    @IBOutlet weak var resuleLabel: UILabel!

    @IBAction func startButton(_ sender: UIButton) {

        if #available(iOS 13.0, *) {
            let nvc = UINavigationController(rootViewController: CreditCardReaderViewController{[weak self] in
                print($0, $1)
                self?.resuleLabel.text = ($0 + "\n" + "\($1.0)" + "\($1.1)")
            })
            nvc.modalPresentationStyle = .fullScreen
            present(nvc, animated: true, completion: nil)
        }
    }
}

