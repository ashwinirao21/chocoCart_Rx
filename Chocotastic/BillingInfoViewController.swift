/// Copyright (c) 2019 Razeware LLC
///
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
///
/// The above copyright notice and this permission notice shall be included in
/// all copies or substantial portions of the Software.
///
/// Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
/// distribute, sublicense, create a derivative work, and/or sell copies of the
/// Software in any work that is designed, intended, or marketed for pedagogical or
/// instructional purposes related to programming, coding, application development,
/// or information technology.  Permission for such use, copying, modification,
/// merger, publication, distribution, sublicensing, creation of derivative works,
/// or sale is expressly withheld.
///
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
/// THE SOFTWARE.

import UIKit
import RxSwift
import RxCocoa

class BillingInfoViewController: UIViewController {
  @IBOutlet private var creditCardNumberTextField: ValidatingTextField!
  @IBOutlet private var creditCardImageView: UIImageView!
  @IBOutlet private var expirationDateTextField: ValidatingTextField!
  @IBOutlet private var cvvTextField: ValidatingTextField!
  @IBOutlet private var purchaseButton: UIButton!
  private let throttleIntervalInMilliseconds = 100 //throttle = how quickly the user’s input moves through a validation process. This means you’ll only validate the input at the throttle interval rather than every time it changes. This way, fast typing won’t grind your whole app to a halt.
  
  private let cardType: BehaviorRelay<CardType> = BehaviorRelay(value: .unknown)
  private let disposeBag = DisposeBag()

}

// MARK: - View Lifecycle
extension BillingInfoViewController {
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "💳 Info"
    
    setupCardImageDisplay()
    setupTextChangeHandling()

  }
  
  override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
    let identifier = self.identifier(forSegue: segue)
    switch identifier {
    case .purchaseSuccess:
      guard let destination = segue.destination as? ChocolateIsComingViewController else {
        assertionFailure("Couldn't get chocolate is coming VC!")
        return
      }
      destination.cardType = cardType.value
    }
  }
}

//MARK: - RX Setup
private extension BillingInfoViewController {
  
  func setupCardImageDisplay() {
    cardType
      .asObservable()
      .subscribe(onNext: { [unowned self] cardType in
        self.creditCardImageView.image = cardType.image
      })
      .disposed(by: disposeBag)
    
    /*
     Add an Observer to the value of a BehaviorRelay.
     Subscribe to that Observable to reveal changes to cardType.
     Ensure the observer’s disposal in thedisposeBag.
     */
  }
  
  func setupTextChangeHandling() {
    let creditCardValid = creditCardNumberTextField
      .rx
      .text //1
      .observeOn(MainScheduler.asyncInstance)
      .distinctUntilChanged()
      .throttle(.milliseconds(throttleIntervalInMilliseconds), scheduler: MainScheduler.instance) //2
      .map { [unowned self] in
        self.validate(cardText: $0) //3
    }
      
    creditCardValid
      .subscribe(onNext: { [unowned self] in
        self.creditCardNumberTextField.valid = $0 //4
      })
      .disposed(by: disposeBag) //5
    
    /*
     Return the the contents of the text field as an Observable value. text is another RxCocoa extension, this time to UITextField.
     Throttle the input to set up the validation to run based on the interval defined above. The scheduler parameter is a more advanced concept, but the short version is that it’s tied to a thread. To keep everything on the main thread, use MainScheduler.
     Transform the throttled input by applying it to validate(cardText:) provided by the class. If the card input is valid, the ultimate value of the observed boolean will be true.
     Take the Observable value you’ve created and subscribe to it, updating the validity of the text field based on the incoming value.
     Add the resulting Disposable to the disposeBag.
     */
    
    let expirationValid = expirationDateTextField
      .rx
      .text
      .observeOn(MainScheduler.asyncInstance)
      .distinctUntilChanged()
      .throttle(.milliseconds(throttleIntervalInMilliseconds), scheduler: MainScheduler.instance)
      .map { [unowned self] in
        self.validate(expirationDateText: $0)
    }
        
    expirationValid
      .subscribe(onNext: { [unowned self] in
        self.expirationDateTextField.valid = $0
      })
      .disposed(by: disposeBag)
        
    let cvvValid = cvvTextField
      .rx
      .text
      .observeOn(MainScheduler.asyncInstance)
      .distinctUntilChanged()
      .map { [unowned self] in
        self.validate(cvvText: $0)
    }
        
    cvvValid
      .subscribe(onNext: { [unowned self] in
        self.cvvTextField.valid = $0
      })
      .disposed(by: disposeBag)

      //...
    
    let everythingValid = Observable
      .combineLatest(creditCardValid, expirationValid, cvvValid) {
        $0 && $1 && $2 //All must be true
    }
        
    everythingValid
      .bind(to: purchaseButton.rx.isEnabled)
      .disposed(by: disposeBag)

    /*
     This uses Observable’s combineLatest(_:) to take the three observables you’ve already made and generate a fourth. The generated Observable, called everythingValid, is either true or false, depending on whether all three inputs are valid.

     everythingValid reflects the isEnabled property on UIButton‘s reactive extension. everythingValid’s value controls the state of the purchase button.

     If all three fields are valid, the underlying value of everythingValid will be true. If not, the underlying value will be false. In either case, rx.isEnabled will apply the value to the purchase button, which is only enabled when all the the credit card details are valid. */
    
    
    
  }
  
  


}

//MARK: - Validation methods
private extension BillingInfoViewController {
  func validate(cardText: String?) -> Bool {
    guard let cardText = cardText else {
      return false
    }
    let noWhitespace = cardText.removingSpaces
    
    updateCardType(using: noWhitespace)
    formatCardNumber(using: noWhitespace)
    advanceIfNecessary(noSpacesCardNumber: noWhitespace)
    
    guard cardType.value != .unknown else {
      //Definitely not valid if the type is unknown.
      return false
    }
    
    guard noWhitespace.isLuhnValid else {
      //Failed luhn validation
      return false
    }
    
    return noWhitespace.count == cardType.value.expectedDigits
  }
  
  func validate(expirationDateText expiration: String?) -> Bool {
    guard let expiration = expiration else {
      return false
    }
    let strippedSlashExpiration = expiration.removingSlash
    
    formatExpirationDate(using: strippedSlashExpiration)
    advanceIfNecessary(expirationNoSpacesOrSlash:  strippedSlashExpiration)
    
    return strippedSlashExpiration.isExpirationDateValid
  }
  
  func validate(cvvText cvv: String?) -> Bool {
    guard let cvv = cvv else {
      return false
    }
    guard cvv.areAllCharactersNumbers else {
      //Someone snuck a letter in here.
      return false
    }
    dismissIfNecessary(cvv: cvv)
    return cvv.count == cardType.value.cvvDigits
  }
}

//MARK: Single-serve helper functions
private extension BillingInfoViewController {
  func updateCardType(using noSpacesNumber: String) {
    cardType.accept(CardType.fromString(string: noSpacesNumber))
  }
  
  func formatCardNumber(using noSpacesCardNumber: String) {
    creditCardNumberTextField.text = cardType.value.format(noSpaces: noSpacesCardNumber)
  }
  
  func advanceIfNecessary(noSpacesCardNumber: String) {
    if noSpacesCardNumber.count == cardType.value.expectedDigits {
      expirationDateTextField.becomeFirstResponder()
    }
  }
  
  func formatExpirationDate(using expirationNoSpacesOrSlash: String) {
    expirationDateTextField.text = expirationNoSpacesOrSlash.addingSlash
  }
  
  func advanceIfNecessary(expirationNoSpacesOrSlash: String) {
    if expirationNoSpacesOrSlash.count == 6 { //mmyyyy
      cvvTextField.becomeFirstResponder()
    }
  }
  
  func dismissIfNecessary(cvv: String) {
    if cvv.count == cardType.value.cvvDigits {
      let _ = cvvTextField.resignFirstResponder()
    }
  }
}

// MARK: - SegueHandler
extension BillingInfoViewController: SegueHandler {
  enum SegueIdentifier: String {
    case purchaseSuccess
  }
}

