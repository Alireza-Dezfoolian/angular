import {Type} from 'angular2/src/core/facade/lang';
import {GetterFn, SetterFn, MethodFn} from './types';

export interface PlatformReflectionCapabilities {
  isReflectionEnabled(): boolean;
  factory(type: Type): Function;
  interfaces(type: Type): any[];
  parameters(type: any): any[][];
  annotations(type: any): any[];
  propMetadata(typeOrFunc: any): StringMap<string, any[]>;
  getter(name: string): GetterFn;
  setter(name: string): SetterFn;
  method(name: string): MethodFn;
  // TODO(tbosch): remove this method after the new compiler is done
  // (and ComponentUrlMapper as well).
  importUri(type: Type): string;
  moduleId(type: Type): string;
}
