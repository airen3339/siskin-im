//
// BaseChatViewController.swift
//
// Tigase iOS Messenger
// Copyright (C) 2016 "Tigase, Inc." <office@tigase.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License,
// or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. Look for COPYING file in the top folder.
// If not, see http://www.gnu.org/licenses/.
//

import UIKit
import UserNotifications
import TigaseSwift

class BaseChatViewController: UIViewController, UITextViewDelegate {

    @IBOutlet var tableView: UITableView!
    @IBOutlet var messageField: UITextView!
    @IBOutlet var sendButton: UIButton!
    @IBOutlet var bottomView: UIView!
    
    var bottomViewBottomConstraint: NSLayoutConstraint?;
    
    var PLACEHOLDER_TEXT = "Enter message...";
    
    @IBInspectable var scrollToBottomOnShow: Bool = false;
    @IBInspectable var animateScrollToBottom: Bool = true;
    
    var dbConnection:DBConnection {
        let appDelegate = UIApplication.shared.delegate as! AppDelegate;
        return appDelegate.dbConnection;
    }
    
    var xmppService:XmppService! {
        let appDelegate = UIApplication.shared.delegate as! AppDelegate;
        return appDelegate.xmppService;
    }
    
    var account:BareJID!;
    var jid:JID!;
    
    weak var scrollDelegate: BaseChatViewControllerScrollDelegate?;
    var isFirstTime = true;
    
    lazy var loadChatInfo:DBStatement! = try? self.dbConnection.prepareStatement("SELECT name FROM roster_items WHERE account = :account AND jid = :jid");
    
    override func viewDidLoad() {
        PLACEHOLDER_TEXT = "from \(account.stringValue)...";
        super.viewDidLoad()
        isFirstTime = scrollToBottomOnShow;

        navigationItem.leftBarButtonItem = splitViewController?.displayModeButtonItem;
        navigationItem.leftItemsSupplementBackButton = true;
        navigationItem.title = jid.stringValue;
        let params:[String:Any?] = ["account" : account, "jid" : jid.bareJid];
        try! loadChatInfo.query(params) { (cursor) -> Void in
            self.navigationItem.title = cursor["name"];
        }
        
        messageField.layer.borderColor = UIColor.lightGray.cgColor;
        messageField.layer.borderWidth = 0.5;
        messageField.layer.cornerRadius = 5.0;
        messageField.layer.masksToBounds = true;
        messageField.delegate = self;
        messageField.isScrollEnabled = false;
        
        tableView.rowHeight = UITableViewAutomaticDimension;
        tableView.estimatedRowHeight = 160.0;
        tableView.separatorStyle = .none;
        
        applyPlaceHolderStyle(messageField);
        
        bottomView.layer.borderColor = UIColor.lightGray.cgColor;
        bottomView.layer.borderWidth = 0.5;
        bottomViewBottomConstraint = view.bottomAnchor.constraint(equalTo: bottomView.bottomAnchor, constant: 0);
        bottomViewBottomConstraint?.isActive = true;
    }

    override func didReceiveMemoryWarning() {
        
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
   
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        NotificationCenter.default.addObserver(self, selector: #selector(ChatViewController.keyboardWillShow), name: NSNotification.Name.UIKeyboardWillShow, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(ChatViewController.keyboardWillHide), name: NSNotification.Name.UIKeyboardWillHide, object: nil);
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated);
        if isFirstTime {
            // scroll to bottom?
            scrollToNewestMessage(animated: true);
            isFirstTime = false;
        }
        let accountStr = account.stringValue;
        let jidStr = jid.bareJid.stringValue;
        UNUserNotificationCenter.current().getDeliveredNotifications { (notifications) in
            var toRemove = [String]();
            for notification in notifications {
                if (notification.request.content.userInfo["account"] as? String) == accountStr && (notification.request.content.userInfo["sender"] as? String) == jidStr {
                    toRemove.append(notification.request.identifier);
                }
            }
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: toRemove);
            self.xmppService.dbChatHistoryStore.markAsRead(for: self.account, with: self.jid.bareJid);
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        NotificationCenter.default.removeObserver(self);
        super.viewDidDisappear(animated);
    }
    
    func keyboardWillShow(_ notification: NSNotification) {
        keyboardAnimateHideShow(notification, hide: false);
    }
    
    func keyboardWillHide(_ notification: NSNotification) {
        keyboardAnimateHideShow(notification, hide: true);
    }
    
    func keyboardAnimateHideShow(_ notification: NSNotification, hide: Bool) {
        if let userInfo = notification.userInfo {
            if let keyboardSize = (userInfo[UIKeyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
                let oldHeight = bottomViewBottomConstraint?.constant ?? CGFloat(0);
                let newHeight = hide ? 0 : keyboardSize.height;
                if (oldHeight - newHeight) != 0 {
                    let duration = userInfo[UIKeyboardAnimationDurationUserInfoKey] as! TimeInterval;
                    let curve = userInfo[UIKeyboardAnimationCurveUserInfoKey] as! UInt;
                    bottomViewBottomConstraint?.constant = newHeight;
                    UIView.animate(withDuration: duration, delay: 0.0, options: [UIViewAnimationOptions(rawValue: curve), UIViewAnimationOptions.layoutSubviews, UIViewAnimationOptions.beginFromCurrentState], animations: {
                        self.view.layoutIfNeeded();
                        self.scrollToNewestMessage(animated: true);
                        
                        }, completion: nil);
                }
            }
        }
    }

    func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
        if textView == messageField && textView.text == PLACEHOLDER_TEXT {
            DispatchQueue.main.async() {
                textView.selectedRange = NSMakeRange(0, 0);
            }
        }
        return true;
    }
    
    func applyPlaceHolderStyle(_ textView: UITextView) {
        textView.textColor = UIColor.lightGray;
        textView.text = PLACEHOLDER_TEXT;
        DispatchQueue.main.async() {
            textView.selectedRange = NSMakeRange(0, 0);
        }
    }
    
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let newLength = textView.text.utf16.count + text.utf16.count - range.length;
        if newLength > 0 {
            if textView == messageField && textView.text == PLACEHOLDER_TEXT {
                if text.utf16.count == 0 {
                    return false;
                }
                textView.textColor = UIColor.darkText;
                textView.alpha = 1.0;
                textView.text = "";
            }
            return true;
        } else {
            applyPlaceHolderStyle(textView);
            return false;
        }
    }
    
    @IBAction func tableViewClicked(_ sender: AnyObject) {
        messageField.resignFirstResponder();
    }
    
    func textViewDidEndEditing(_ textView: UITextView) {
        textView.resignFirstResponder();
    }
    
    func scrollToNewestMessage(animated: Bool) {
        if scrollDelegate != nil {
            scrollDelegate?.tableViewScrollToNewestMessage(animated: animated)
        } else {
            scrollToNewestMessageImpl(animated: animated);
        }
    }
    
    func scrollToNewestMessageImpl(animated: Bool) {
        func scrollToNewestMessage(_ animated: Bool) {
            let count = xmppService.dbChatHistoryStore.countMessages(for: account, with: jid.bareJid);
            if count > 0 {
                let path = IndexPath(row: count - 1, section: 0);
                self.tableView.scrollToRow(at: path, at: .bottom, animated: animated);
            }
        }
    }
    
}

protocol BaseChatViewControllerScrollDelegate: class {
    
    func tableViewScrollToNewestMessage(animated: Bool);
    
}
