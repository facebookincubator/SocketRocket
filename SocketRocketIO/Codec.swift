//
//  Codec.swift
//  SocketRocket
//
//  Created by Mike Lewis on 1/6/16.
//
//

import RxSwift

enum ValueOrEnd<V> {
    /// :param consumed: the size of the input stream consumed
    /// :param value: result value for the coded
    case Value(V)
    
    /// If we're out of data
    case End
}

//
protocol Codec {
    typealias InputElement
    typealias OutputElement
    
    /// Consumes all the input. Appends
    mutating func code<
        I: CollectionType,
        O: RangeReplaceableCollectionType
        where
        I.Generator.Element == InputElement,
        O.Generator.Element == OutputElement,
        I.Index.Distance == Int
        >(input: ValueOrEnd<I>, inout output: O) throws
}



extension ObservableType where E: CollectionType, E.Index.Distance == Int {
    func encode<C: Codec where C.InputElement == E.Generator.Element>(codecFactory: () -> C) -> Observable<[C.OutputElement]>{
        return Observable.create { observer in
            var codec = codecFactory()
            var outputBuffer = Array<C.OutputElement>()
            
            return self.subscribe { event in
                defer { outputBuffer.removeAll(keepCapacity: true) }
                
                do {
                    switch event {
                    case .Completed:
                        try codec.code(ValueOrEnd<Array<C.InputElement>>.End, output: &outputBuffer)
                        if !outputBuffer.isEmpty {
                            observer.onNext(outputBuffer)
                        }
                        observer.onCompleted()
                    case let .Error(e):
                        throw e
                        
                    case let .Next(value):
                        try codec.code(.Value(value), output: &outputBuffer)
                        observer.onNext(outputBuffer)
                    }
                } catch let e {
                    observer.onError(e)
                }
            }
        }
    }
}