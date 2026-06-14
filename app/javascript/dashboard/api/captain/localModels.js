/* global axios */
import ApiClient from '../ApiClient';

class CaptainLocalModels extends ApiClient {
  constructor() {
    super('captain/local_models', { accountScoped: true });
  }

  get() {
    return axios.get(this.url);
  }
}

export default new CaptainLocalModels();