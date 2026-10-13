import { registerPlugin } from '@capacitor/core';

interface UpiPlugin {
  pay(options: { uri: string }): Promise<void>;
}

const Upi = registerPlugin<UpiPlugin>('Upi');

export default Upi;
